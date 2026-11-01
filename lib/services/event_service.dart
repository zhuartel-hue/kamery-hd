import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera.dart';
import 'camera_api.dart';
import 'camera_http.dart';
import 'camera_store.dart';
import 'event_parser.dart';

/// Wykrycie osoby: kamera, chwila, rodzaj zdarzenia i zdjęcie z tej chwili.
class Detection {
  Detection({required this.camera, required this.time, required this.kind, this.image});
  final Camera camera;
  final DateTime time;
  final String kind;
  Uint8List? image;
}

/// Nasłuchuje zdarzeń „osoba” z kamer i rejestratorów (wykrywanie robi samo urządzenie:
/// Hikvision AcuSense / wtargnięcie / linia, Dahua SMD / IVS). Działa, gdy aplikacja
/// jest otwarta - iPhone wstrzymuje połączenia w tle.
class EventService extends ChangeNotifier {
  EventService._();
  static final EventService instance = EventService._();

  static const _enabledKey = 'personAlerts';
  static const maxDetections = 100;

  /// Ten sam alarm z jednej kamery przychodzi wiele razy - pokazujemy go raz na tyle sekund.
  static const _repeatGap = Duration(seconds: 20);

  bool enabled = false;
  final List<Detection> detections = [];
  int unread = 0;

  /// Stan połączenia z każdym urządzeniem (nazwa → opis).
  final Map<String, String> status = {};

  final _controller = StreamController<Detection>.broadcast();
  Stream<Detection> get onDetection => _controller.stream;

  final Map<String, _DeviceListener> _listeners = {};
  final Map<String, DateTime> _lastAlert = {};
  List<Camera> _cameras = const [];
  AppLifecycleListener? _lifecycle;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_enabledKey) ?? false;
    _lifecycle ??= AppLifecycleListener(onResume: _restart);
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    update(await CameraStore().load());
    notifyListeners();
  }

  void markRead() {
    if (unread == 0) return;
    unread = 0;
    notifyListeners();
  }

  void clear() {
    detections.clear();
    unread = 0;
    notifyListeners();
  }

  static String deviceKey(Camera c) => '${c.brand.name}|${c.host}|${c.httpPort}|${c.user}';

  /// Wywoływane po każdej zmianie listy kamer: jedno połączenie na urządzenie.
  void update(List<Camera> cameras) {
    _cameras = cameras;
    final groups = <String, List<Camera>>{};
    if (enabled) {
      for (final c in cameras) {
        if (c.host.isEmpty) continue;
        groups.putIfAbsent(deviceKey(c), () => []).add(c);
      }
    }
    for (final key in _listeners.keys.toList()) {
      if (!groups.containsKey(key)) {
        _listeners.remove(key)!.stop();
        status.remove(key);
      }
    }
    for (final e in groups.entries) {
      final existing = _listeners[e.key];
      if (existing != null) {
        existing.cameras = e.value;
      } else {
        _listeners[e.key] = _DeviceListener(this, e.key, e.value)..start();
      }
    }
    notifyListeners();
  }

  /// Po powrocie aplikacji z tła stare połączenia są zwykle zerwane - zaczynamy od nowa.
  void _restart() {
    for (final l in _listeners.values) {
      l.stop();
    }
    _listeners.clear();
    update(_cameras);
  }

  void _setStatus(String key, String text) {
    if (status[key] == text) return;
    status[key] = text;
    notifyListeners();
  }

  Future<void> _onEvent(List<Camera> cameras, PersonEvent e) async {
    final camera = cameras.where((c) => c.channel == e.channel).firstOrNull ?? (cameras.length == 1 ? cameras.first : null);
    if (camera == null) return; // kanał, którego nie ma w aplikacji
    final now = DateTime.now();
    final last = _lastAlert[camera.id];
    if (last != null && now.difference(last) < _repeatGap) return;
    _lastAlert[camera.id] = now;

    final d = Detection(camera: camera, time: now, kind: e.kind);
    detections.insert(0, d);
    if (detections.length > maxDetections) detections.removeRange(maxDetections, detections.length);
    unread++;
    HapticFeedback.heavyImpact();
    notifyListeners();

    final api = CameraApi(camera);
    try {
      d.image = await api.snapshot();
    } on CameraException {
      // bez zdjęcia - zdarzenie i tak jest na liście
    } catch (_) {
      // błąd sieci przy zdjęciu nie może przerwać nasłuchu
    } finally {
      api.close();
    }
    _controller.add(d);
    notifyListeners();
  }
}

class _DeviceListener {
  _DeviceListener(this.service, this.key, this.cameras);

  final EventService service;
  final String key;
  List<Camera> cameras;

  bool _stopped = false;
  CameraHttp? _http;

  /// Brak jakichkolwiek danych przez tyle czasu = połączenie martwe, łączymy od nowa.
  static const _silence = Duration(seconds: 90);

  String get _name {
    final c = cameras.first;
    return cameras.length > 1 ? 'Rejestrator ${c.brandLabel} ${c.host}' : c.name;
  }

  void start() => unawaited(_loop());

  void stop() {
    _stopped = true;
    _http?.close();
  }

  Future<void> _loop() async {
    var delay = const Duration(seconds: 3);
    while (!_stopped) {
      try {
        await _listenOnce();
        delay = const Duration(seconds: 3);
      } catch (e) {
        if (_stopped) break;
        service._setStatus(key, '$_name: brak połączenia ($e), ponawiam…');
      }
      if (_stopped) break;
      await Future<void>.delayed(delay);
      delay = Duration(seconds: min(delay.inSeconds * 2, 60));
    }
  }

  Future<void> _listenOnce() async {
    final c = cameras.first;
    final http = CameraHttp(c.user, c.password);
    _http = http;
    try {
      final url = c.isHikvision
          ? '${c.httpBase}/ISAPI/Event/notification/alertStream'
          : '${c.httpBase}/cgi-bin/eventManager.cgi?action=attach&codes=[All]&heartbeat=5';
      final stream = await http.openStream(url);
      service._setStatus(key, '$_name: nasłuchuję');
      final hik = HikEventParser();
      final dahua = DahuaEventParser();
      await for (final text in const Utf8Decoder(allowMalformed: true).bind(stream).timeout(_silence)) {
        if (_stopped) break;
        final events = c.isHikvision ? hik.feed(text) : dahua.feed(text);
        for (final e in events) {
          unawaited(service._onEvent(cameras, e));
        }
      }
    } finally {
      http.close();
      if (_http == http) _http = null;
    }
  }
}

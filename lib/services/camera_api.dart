import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/camera.dart';
import 'camera_http.dart';

enum PtzMove { up, down, left, right, zoomIn, zoomOut }

class CameraException implements Exception {
  CameraException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Funkcje zależne od producenta: test połączenia, zdjęcie, sterowanie PTZ.
class CameraApi {
  CameraApi(this.camera) : _http = CameraHttp(camera.user, camera.password);

  final Camera camera;
  final CameraHttp _http;

  static const _hikSpeed = 60; // zakres 1..100
  static const _dahuaSpeed = 5; // zakres 1..8

  void close() => _http.close();

  /// Zwraca opis urządzenia (model, firmware) lub rzuca [CameraException].
  Future<String> deviceInfo() async {
    final r = await _call(() => _http.get(camera.deviceInfoUrl));
    final text = r.text;
    final parts = camera.isHikvision
        ? [
            _xmlTag(text, 'deviceName'),
            _xmlTag(text, 'model'),
            _prefix('firmware ', _xmlTag(text, 'firmwareVersion')),
          ]
        : [
            _keyValue(text, 'deviceType'),
            _prefix('S/N ', _keyValue(text, 'serialNumber')),
          ];
    final info = parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    return info.isEmpty ? 'Połączono' : info;
  }

  Future<Uint8List> snapshot() async {
    final r = await _call(() => _http.get(camera.snapshotUrl));
    final b = r.body;
    if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) {
      throw CameraException('Kamera nie zwróciła obrazu JPEG');
    }
    return b;
  }

  Future<void> ptzStart(PtzMove move) async {
    if (camera.isHikvision) {
      final s = _hikSpeed;
      final (pan, tilt, zoom) = switch (move) {
        PtzMove.up => (0, s, 0),
        PtzMove.down => (0, -s, 0),
        PtzMove.left => (-s, 0, 0),
        PtzMove.right => (s, 0, 0),
        PtzMove.zoomIn => (0, 0, s),
        PtzMove.zoomOut => (0, 0, -s),
      };
      await _hikContinuous(pan, tilt, zoom);
    } else {
      await _dahuaPtz('start', move);
    }
  }

  Future<void> ptzStop(PtzMove move) async {
    if (camera.isHikvision) {
      await _hikContinuous(0, 0, 0);
    } else {
      await _dahuaPtz('stop', move);
    }
  }

  Future<void> _hikContinuous(int pan, int tilt, int zoom) => _call(() => _http.put(
        '${camera.httpBase}/ISAPI/PTZCtrl/channels/${camera.channel}/continuous',
        '<?xml version="1.0" encoding="UTF-8"?><PTZData>'
            '<pan>$pan</pan><tilt>$tilt</tilt><zoom>$zoom</zoom></PTZData>',
        'application/xml',
      ));

  Future<void> _dahuaPtz(String action, PtzMove move) {
    final code = switch (move) {
      PtzMove.up => 'Up',
      PtzMove.down => 'Down',
      PtzMove.left => 'Left',
      PtzMove.right => 'Right',
      PtzMove.zoomIn => 'ZoomTele',
      PtzMove.zoomOut => 'ZoomWide',
    };
    // W ptz.cgi Dahua kanały numerowane są od 0.
    return _call(() => _http.get('${camera.httpBase}/cgi-bin/ptz.cgi?action=$action'
        '&channel=${camera.channel - 1}&code=$code&arg1=0&arg2=$_dahuaSpeed&arg3=0'));
  }

  /// Wykonuje zapytanie i zamienia błędy sieci/HTTP na czytelne komunikaty.
  static Future<CameraResponse> _call(Future<CameraResponse> Function() fn) async {
    final CameraResponse r;
    try {
      r = await fn();
    } on TimeoutException {
      throw CameraException('Brak odpowiedzi – sprawdź adres, port HTTP i sieć');
    } on SocketException catch (e) {
      if (e.osError?.message.toLowerCase().contains('refused') ?? false) {
        throw CameraException('Połączenie odrzucone – sprawdź port HTTP');
      }
      throw CameraException('Brak połączenia z kamerą (${e.osError?.message ?? e.message})');
    } on HttpException catch (e) {
      throw CameraException('Błąd HTTP: ${e.message}');
    } on FormatException {
      throw CameraException('Nieprawidłowy adres kamery');
    }
    switch (r.statusCode) {
      case 401:
        throw CameraException('Błędny użytkownik lub hasło (401)');
      case 403:
        throw CameraException('Brak uprawnień (403)');
      case 404:
        throw CameraException('Funkcja niedostępna w tym urządzeniu (404)');
    }
    if (r.statusCode >= 400) throw CameraException('Błąd urządzenia: HTTP ${r.statusCode}');
    return r;
  }

  static String? _xmlTag(String xml, String tag) =>
      RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml)?.group(1)?.trim();

  static String? _keyValue(String text, String key) =>
      RegExp('^$key=(.*)\$', multiLine: true).firstMatch(text)?.group(1)?.trim();

  static String? _prefix(String p, String? v) => v == null ? null : '$p$v';
}

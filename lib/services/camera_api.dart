import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/camera.dart';
import '../models/discovered_channel.dart';
import '../models/recording.dart';
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

  /// Czy kamera jest obrotowa (obsługuje PTZ). Błąd lub brak funkcji = nie.
  Future<bool> detectPtz() async {
    try {
      if (camera.isHikvision) {
        final r = await _call(() => _http.get('${camera.httpBase}/ISAPI/PTZCtrl/channels/${camera.channel}/capabilities'));
        return r.text.contains('PTZChanelCap') || r.text.contains('PTZChannelCap') || r.text.contains('ContinuousPanTiltSpace');
      }
      final r = await _call(() => _http.get(
          '${camera.httpBase}/cgi-bin/ptz.cgi?action=getCurrentProtocolCaps&channel=${camera.channel - 1}'));
      return r.text.contains('caps.') && !r.text.contains('caps.Pan=false');
    } on CameraException {
      return false;
    }
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

  /// Kanały rejestratora NVR/DVR (dla zwykłej kamery zwykle jeden).
  Future<List<DiscoveredChannel>> discoverChannels() async {
    if (camera.isHikvision) {
      final r = await _call(() => _http.get('${camera.httpBase}/ISAPI/Streaming/channels'));
      final channels = parseHikChannels(r.text);
      // Stan kamer IP podaje tylko rejestrator; zwykła kamera zwraca tu 404.
      Map<int, bool> status = const {};
      try {
        final st = await _call(() => _http.get('${camera.httpBase}/ISAPI/ContentMgmt/InputProxy/channels/status'));
        status = parseHikChannelStatus(st.text);
      } on CameraException {
        // brak informacji o stanie - nie przeszkadza
      }
      return [for (final c in channels) c.withOnline(status[c.channel])];
    }
    final r = await _call(() => _http.get('${camera.httpBase}/cgi-bin/configManager.cgi?action=getConfig&name=ChannelTitle'));
    final channels = parseDahuaChannelTitles(r.text);
    Map<int, bool> status = const {};
    try {
      // Stan jest dodatkiem: jeśli firmware nie zrozumie zakodowanych nawiasów, lista
      // kanałów i tak się pojawi, tylko bez informacji o podłączeniu.
      final st = await _call(() => _http.get(
          '${camera.httpBase}/cgi-bin/LogicDeviceManager.cgi?action=getCameraState&uniqueChannels[0]=-1'));
      status = parseDahuaCameraState(st.text);
    } on CameraException {
      // zwykła kamera Dahua nie ma tej funkcji
    }
    return [for (final c in channels) c.withOnline(status[c.channel])];
  }

  /// Hikvision /ISAPI/Streaming/channels: identyfikatory 101, 201… to strumienie
  /// główne kolejnych kanałów (102, 202… - pomocnicze, pomijamy).
  static List<DiscoveredChannel> parseHikChannels(String xml) {
    final result = <int, DiscoveredChannel>{};
    for (final m in RegExp(r'<StreamingChannel[ >](.*?)</StreamingChannel>', dotAll: true).allMatches(xml)) {
      final block = m.group(1)!;
      final id = int.tryParse(_xmlTag(block, 'id') ?? '');
      if (id == null || id % 100 != 1) continue;
      final channel = id ~/ 100;
      final name = _xmlTag(block, 'channelName') ?? '';
      result[channel] = DiscoveredChannel(channel, name.isEmpty ? 'Kanał $channel' : name);
    }
    return result.values.toList()..sort((a, b) => a.channel.compareTo(b.channel));
  }

  /// Hikvision InputProxy/channels/status: id kanału IP i czy kamera jest online.
  static Map<int, bool> parseHikChannelStatus(String xml) {
    final result = <int, bool>{};
    for (final m in RegExp(r'<InputProxyChannelStatus[ >](.*?)</InputProxyChannelStatus>', dotAll: true)
        .allMatches(xml)) {
      final id = int.tryParse(_xmlTag(m.group(1)!, 'id') ?? '');
      final online = _xmlTag(m.group(1)!, 'online');
      if (id != null && online != null) result[id] = online == 'true';
    }
    return result;
  }

  /// Dahua ChannelTitle: table.ChannelTitle[0].Name=… - kanały numerowane od 0.
  static List<DiscoveredChannel> parseDahuaChannelTitles(String text) {
    final result = <DiscoveredChannel>[];
    for (final m in RegExp(r'^table\.ChannelTitle\[(\d+)\]\.Name=(.*?)\r?$', multiLine: true).allMatches(text)) {
      final channel = int.parse(m.group(1)!) + 1;
      final name = m.group(2)!.trim();
      result.add(DiscoveredChannel(channel, name.isEmpty ? 'Kanał $channel' : name));
    }
    return result..sort((a, b) => a.channel.compareTo(b.channel));
  }

  /// Dahua getCameraState: states[i].channel (od 0) i connectionState.
  static Map<int, bool> parseDahuaCameraState(String text) {
    final channels = <int, int>{};
    final states = <int, String>{};
    for (final m in RegExp(r'^states\[(\d+)\]\.(channel|connectionState)=(.*?)\r?$', multiLine: true)
        .allMatches(text)) {
      final i = int.parse(m.group(1)!);
      if (m.group(2) == 'channel') {
        channels[i] = int.tryParse(m.group(3)!.trim()) ?? -1;
      } else {
        states[i] = m.group(3)!.trim();
      }
    }
    return {
      for (final i in channels.keys)
        if (channels[i]! >= 0 && states[i] != null) channels[i]! + 1: states[i] == 'Connected',
    };
  }

  /// Lista nagrań z danego dnia (z rejestratora albo karty SD kamery).
  Future<List<Recording>> recordings(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final found = camera.isHikvision ? await _hikSearch(from, to) : await _dahuaSearch(from, to);
    return Recording.merge(found);
  }

  Future<List<Recording>> _hikSearch(DateTime from, DateTime to) async {
    final url = '${camera.httpBase}/ISAPI/ContentMgmt/search';
    final result = <Recording>[];
    String iso(DateTime t) => '${t.toIso8601String().substring(0, 19)}Z';
    for (var page = 0; page < 20; page++) {
      final body = '<?xml version="1.0" encoding="UTF-8"?><CMSearchDescription>'
          '<searchID>${_uuid()}</searchID>'
          '<trackList><trackID>${camera.channel}01</trackID></trackList>'
          '<timeSpanList><timeSpan><startTime>${iso(from)}</startTime>'
          '<endTime>${iso(to)}</endTime></timeSpan></timeSpanList>'
          '<maxResults>50</maxResults>'
          // „Postion” - tak (z literówką) nazywa to pole Hikvision.
          '<searchResultPostion>${result.length}</searchResultPostion>'
          '<metadataList><metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor></metadataList>'
          '</CMSearchDescription>';
      final r = await _call(() => _http.request('POST', url, body: body, contentType: 'application/xml'));
      final (items, more) = parseHikSearch(r.text);
      result.addAll(items);
      if (!more || items.isEmpty) break;
    }
    return result;
  }

  Future<List<Recording>> _dahuaSearch(DateTime from, DateTime to) async {
    final base = '${camera.httpBase}/cgi-bin/mediaFileFind.cgi';
    String fmt(DateTime t) => Uri.encodeQueryComponent(t.toIso8601String().substring(0, 19).replaceFirst('T', ' '));
    final created = await _call(() => _http.get('$base?action=factory.create'));
    final object = RegExp(r'result=(\d+)').firstMatch(created.text)?.group(1);
    if (object == null) throw CameraException('Rejestrator nie obsługuje wyszukiwania nagrań');
    final result = <Recording>[];
    try {
      await _call(() => _http.get('$base?action=findFile&object=$object'
          '&condition.Channel=${camera.channel}'
          // Bez filtra condition.Types[0]=dav: Dart koduje nawiasy (%5B0%5D), czego część
          // firmware'ów nie rozumie. Pliki inne niż wideo odrzuca parseDahuaFind.
          '&condition.StartTime=${fmt(from)}&condition.EndTime=${fmt(to)}'));
      for (var page = 0; page < 20; page++) {
        final r = await _call(() => _http.get('$base?action=findNextFile&object=$object&count=100'));
        final items = parseDahuaFind(r.text);
        result.addAll(items);
        if (items.length < 100) break;
      }
    } on CameraException catch (e) {
      // Brak nagrań w tym dniu Dahua zgłasza jako błąd zapytania.
      if (!e.message.contains('HTTP 400')) rethrow;
    } finally {
      // Sprzątanie po wyszukiwaniu - błędy tutaj nie są istotne dla użytkownika.
      try {
        await _http.get('$base?action=close&object=$object');
        await _http.get('$base?action=destroy&object=$object');
      } on Exception {
        // ignorujemy
      }
    }
    return result;
  }

  /// Wyniki ISAPI ContentMgmt/search: fragmenty i informacja, czy są kolejne strony.
  static (List<Recording>, bool) parseHikSearch(String xml) {
    final items = <Recording>[];
    for (final m in RegExp(r'<searchMatchItem[^>]*>(.*?)</searchMatchItem>', dotAll: true).allMatches(xml)) {
      final item = m.group(1)!;
      final start = Recording.parseDeviceTime(_xmlTag(item, 'startTime') ?? '');
      final end = Recording.parseDeviceTime(_xmlTag(item, 'endTime') ?? '');
      if (start != null && end != null) items.add(Recording(start, end));
    }
    final status = _xmlTag(xml, 'responseStatusStrg') ?? '';
    return (items, status.toUpperCase() == 'MORE');
  }

  /// Wyniki Dahua mediaFileFind findNextFile (format klucz=wartość).
  static List<Recording> parseDahuaFind(String text) {
    final starts = <int, DateTime>{};
    final ends = <int, DateTime>{};
    final types = <int, String>{};
    for (final m in RegExp(r'^items\[(\d+)\]\.(StartTime|EndTime|Type)=(.*?)\r?$', multiLine: true).allMatches(text)) {
      final i = int.parse(m.group(1)!);
      if (m.group(2) == 'Type') {
        types[i] = m.group(3)!.trim().toLowerCase();
        continue;
      }
      final t = Recording.parseDeviceTime(m.group(3)!);
      if (t == null) continue;
      (m.group(2) == 'StartTime' ? starts : ends)[i] = t;
    }
    return [
      for (final i in starts.keys.toList()..sort())
        // Zdjęcia (jpg) też są „plikami” rejestratora - zostawiamy tylko wideo.
        if (ends[i] != null && (types[i] ?? 'dav') == 'dav') Recording(starts[i]!, ends[i]!),
    ];
  }

  static String _uuid() {
    final r = Random.secure();
    String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}'.toUpperCase();
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

import 'dart:async';
import 'dart:io';

import '../models/camera.dart';
import 'camera_api.dart';

/// Wynik automatycznego wykrywania portów.
class PortDiscoveryResult {
  PortDiscoveryResult({this.httpPort, this.rtspPort, this.brand, this.message = ''});

  /// Port HTTP (web), na którym odpowiedziało urządzenie; null = nie znaleziono.
  final int? httpPort;

  /// Port RTSP (podgląd i nagrania); null = nie znaleziono.
  final int? rtspPort;

  /// Marka rozpoznana po odpowiedzi urządzenia (może różnić się od wybranej).
  final Brand? brand;

  /// Opis dla użytkownika, skąd wzięły się porty.
  final String message;

  bool get found => httpPort != null || rtspPort != null;
}

/// Szuka portów HTTP i RTSP kamery lub rejestratora:
/// 1. sprawdza typowe porty HTTP i rozpoznaje markę (Hikvision ISAPI / Dahua CGI),
/// 2. odczytuje z urządzenia ustawione porty (Hikvision: /ISAPI/Security/adminAccess,
///    Dahua: configManager RTSP i Web),
/// 3. gdy to się nie uda - sprawdza po kolei typowe porty RTSP.
class PortDiscovery {
  static const httpCandidates = [80, 8080, 81, 8081, 88, 8888];
  static const rtspCandidates = [554, 8554, 10554, 5554, 1554];
  static const _probeTimeout = Duration(milliseconds: 1500);

  /// Czy na porcie [port] coś nasłuchuje (zwykłe połączenie TCP).
  static Future<bool> isOpen(String host, int port, {Duration timeout = _probeTimeout}) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  static Camera _copy(Camera c, {int? httpPort, Brand? brand}) {
    final copy = Camera.fromJson(c.toJson());
    if (httpPort != null) copy.httpPort = httpPort;
    if (brand != null) copy.brand = brand;
    return copy;
  }

  static Future<PortDiscoveryResult> discover(Camera camera) async {
    final host = camera.host;
    final httpOrder = <int>{camera.httpPort, ...httpCandidates}.toList();
    final notes = <String>[];

    int? httpPort;
    Brand? brand;
    String? authError;

    // 1. Port HTTP i marka.
    for (final port in httpOrder) {
      if (!await isOpen(host, port)) continue;
      final other = camera.isHikvision ? Brand.dahua : Brand.hikvision;
      for (final b in [camera.brand, other]) {
        final api = CameraApi(_copy(camera, httpPort: port, brand: b));
        try {
          await api.deviceInfo();
          httpPort = port;
          brand = b;
        } on CameraException catch (e) {
          // 401 = port i marka właściwe, tylko złe hasło.
          if (e.message.contains('401')) {
            httpPort = port;
            brand = b;
            authError = e.message;
          }
        } finally {
          api.close();
        }
        if (httpPort != null) break;
      }
      if (httpPort != null) break;
    }

    if (httpPort == null) {
      notes.add('nie znaleziono portu web (sprawdzone: ${httpOrder.join(', ')})');
    }

    // 2. Ustawienia portów odczytane z urządzenia.
    int? rtspPort;
    if (httpPort != null && brand != null && authError == null) {
      final dev = _copy(camera, httpPort: httpPort, brand: brand);
      final api = CameraApi(dev);
      try {
        if (dev.isHikvision) {
          final xml = await api.getText('/ISAPI/Security/adminAccess');
          rtspPort = parseHikAdminAccess(xml, 'RTSP');
        } else {
          final text = await api.getText('/cgi-bin/configManager.cgi?action=getConfig&name=RTSP');
          rtspPort = parseDahuaConfigPort(text, 'RTSP');
        }
      } on CameraException {
        // starsze firmware - przejdziemy do sprawdzania portów
      } finally {
        api.close();
      }
      // Za routerem (DDNS) port z ustawień może być przekierowany na inny - sprawdzamy.
      if (rtspPort != null && !await isOpen(host, rtspPort)) {
        notes.add('urządzenie podaje RTSP $rtspPort, ale port jest zamknięty');
        rtspPort = null;
      } else if (rtspPort != null) {
        notes.add('porty odczytane z urządzenia');
      }
    }

    // 3. Sprawdzanie typowych portów RTSP.
    if (rtspPort == null) {
      final order = <int>{camera.rtspPort, ...rtspCandidates};
      for (final port in order) {
        if (await isOpen(host, port)) {
          rtspPort = port;
          notes.add('port RTSP znaleziony przez sprawdzenie portów');
          break;
        }
      }
      if (rtspPort == null) notes.add('nie znaleziono portu RTSP');
    }

    if (authError != null) notes.add(authError);

    return PortDiscoveryResult(httpPort: httpPort, rtspPort: rtspPort, brand: brand, message: notes.join(' · '));
  }

  /// Hikvision /ISAPI/Security/adminAccess: lista `<AdminAccessProtocol>` z protokołem i portem.
  static int? parseHikAdminAccess(String xml, String protocol) {
    for (final m in RegExp(r'<AdminAccessProtocol[ >](.*?)</AdminAccessProtocol>', dotAll: true).allMatches(xml)) {
      final block = m.group(1)!;
      final p = RegExp(r'<protocol>([^<]*)</protocol>').firstMatch(block)?.group(1)?.trim();
      if (p == null || p.toUpperCase() != protocol.toUpperCase()) continue;
      final port = int.tryParse(RegExp(r'<portNo>([^<]*)</portNo>').firstMatch(block)?.group(1)?.trim() ?? '');
      if (port != null && port > 0) return port;
    }
    return null;
  }

  /// Dahua configManager getConfig: wiersze „table.RTSP.Port=554”, „table.Web.Port=80”.
  static int? parseDahuaConfigPort(String text, String name) {
    final m = RegExp('^table\\.$name\\.Port=(\\d+)', multiLine: true).firstMatch(text);
    final port = int.tryParse(m?.group(1) ?? '');
    return port != null && port > 0 ? port : null;
  }
}

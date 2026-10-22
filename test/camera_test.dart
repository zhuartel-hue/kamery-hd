import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamery_hd/models/camera.dart';
import 'package:kamery_hd/services/camera_api.dart';
import 'package:kamery_hd/services/camera_http.dart';

void main() {
  group('adresy', () {
    test('Hikvision', () {
      final c = Camera(host: '192.168.1.64', user: 'admin', password: 'p@ss:1', channel: 2);
      expect(c.rtspUrl(main: true), 'rtsp://admin:p%40ss%3A1@192.168.1.64:554/Streaming/Channels/201');
      expect(c.rtspUrl(main: false), endsWith('/Streaming/Channels/202'));
      expect(c.snapshotUrl, 'http://192.168.1.64/ISAPI/Streaming/channels/201/picture');
    });

    test('Dahua', () {
      final c = Camera(brand: Brand.dahua, host: 'cam.ddns.net', httpPort: 8080, password: 'x');
      expect(c.rtspUrl(main: false), 'rtsp://admin:x@cam.ddns.net:554/cam/realmonitor?channel=1&subtype=1');
      expect(c.snapshotUrl, 'http://cam.ddns.net:8080/cgi-bin/snapshot.cgi?channel=1');
      expect(c.rtspUrl(main: true, maskPassword: true), contains('admin:****@'));
    });

    test('zapis i odczyt JSON', () {
      final c = Camera(name: 'Wjazd', brand: Brand.dahua, host: '10.0.0.5', channel: 3, mainStream: true);
      final copy = Camera.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
      expect(copy.toJson(), c.toJson());
    });
  });

  test('wyzwanie Digest wycięte z kilku nagłówków', () {
    const both = 'Basic realm="a", Digest qop="auth", realm="b", nonce="n1"';
    const reversed = 'Digest qop="auth", realm="b", nonce="n1", Basic realm="a"';
    for (final h in [both, reversed]) {
      final p = CameraHttp.parseChallenge(CameraHttp.digestChallenge(h)!);
      expect(p['realm'], 'b');
      expect(p['nonce'], 'n1');
    }
    expect(CameraHttp.digestChallenge('Basic realm="a"'), isNull);
  });

  group('autoryzacja Digest (symulowana kamera)', () {
    late HttpServer server;
    const realm = 'IP Camera';
    const nonce = 'abc123nonce';
    String md5s(String s) => md5.convert(utf8.encode(s)).toString();

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
        var ok = false;
        if (auth.startsWith('Digest ')) {
          final p = CameraHttp.parseChallenge(auth.substring(7));
          final ha1 = md5s('${p['username']}:$realm:secret');
          final ha2 = md5s('${req.method}:${p['uri']}');
          ok = p['response'] == md5s('$ha1:$nonce:${p['nc']}:${p['cnonce']}:auth:$ha2') &&
              p['uri'] == req.uri.toString();
        }
        if (!ok) {
          // Jak Hikvision: dwa nagłówki, Basic i Digest.
          req.response.statusCode = 401;
          req.response.headers.add('WWW-Authenticate', 'Basic realm="$realm"');
          req.response.headers.add('WWW-Authenticate', 'Digest qop="auth", realm="$realm", nonce="$nonce"');
        } else if (req.uri.path == '/ISAPI/System/deviceInfo') {
          req.response.write('<DeviceInfo><deviceName>Wjazd</deviceName><model>DS-2CD2143G2-I</model>'
              '<firmwareVersion>V5.7.3</firmwareVersion></DeviceInfo>');
        } else if (req.uri.path == '/cgi-bin/magicBox.cgi') {
          req.response.write('deviceType=IPC-HFW2431S\nserialNumber=ABC123\n');
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Camera cam(Brand brand, String pass) =>
        Camera(brand: brand, host: '127.0.0.1', httpPort: server.port, password: pass);

    test('Hikvision deviceInfo + PTZ (PUT)', () async {
      final api = CameraApi(cam(Brand.hikvision, 'secret'));
      expect(await api.deviceInfo(), 'Wjazd · DS-2CD2143G2-I · firmware V5.7.3');
      await api.ptzStart(PtzMove.left);
      await api.ptzStop(PtzMove.left);
      api.close();
    });

    test('Dahua deviceInfo + PTZ', () async {
      final api = CameraApi(cam(Brand.dahua, 'secret'));
      expect(await api.deviceInfo(), 'IPC-HFW2431S · S/N ABC123');
      await api.ptzStart(PtzMove.zoomIn);
      api.close();
    });

    test('błędne hasło', () async {
      final api = CameraApi(cam(Brand.hikvision, 'zle'));
      await expectLater(api.deviceInfo(),
          throwsA(isA<CameraException>().having((e) => e.message, 'message', contains('401'))));
      api.close();
    });
  });
}


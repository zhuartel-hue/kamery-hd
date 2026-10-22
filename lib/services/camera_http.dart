import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class CameraResponse {
  CameraResponse(this.statusCode, this.body);
  final int statusCode;
  final Uint8List body;
  String get text => utf8.decode(body, allowMalformed: true);
}

/// Zapytania HTTP do kamer. Hikvision (ISAPI) i Dahua (CGI) wymagają zwykle autoryzacji
/// Digest, starsze modele akceptują Basic - obsługujemy obie.
class CameraHttp {
  CameraHttp(this.user, this.password);

  final String user;
  final String password;
  static const timeout = Duration(seconds: 6);

  final HttpClient _client = HttpClient()..connectionTimeout = timeout;

  /// Zapamiętane wyzwanie Digest, żeby kolejne klatki nie wymagały dodatkowego 401.
  Map<String, String>? _digest;
  int _nonceCount = 0;

  Future<CameraResponse> get(String url) => request('GET', url);

  Future<CameraResponse> put(String url, String body, String contentType) =>
      request('PUT', url, body: body, contentType: contentType);

  Future<CameraResponse> request(String method, String url,
      {String? body, String? contentType}) async {
    var r = await _send(method, url, body, contentType);
    if (r.statusCode == 401 && r.challenge != null) {
      final digest = digestChallenge(r.challenge!);
      _digest = digest == null ? null : parseChallenge(digest);
      _nonceCount = 0;
      r = await _send(method, url, body, contentType);
    }
    return CameraResponse(r.statusCode, r.body);
  }

  void close() => _client.close(force: true);

  Future<_RawResponse> _send(String method, String url, String? body, String? contentType) async {
    final uri = Uri.parse(url);
    final req = await _client.openUrl(method, uri).timeout(timeout);
    final auth = _authHeader(method, uri);
    if (auth != null) req.headers.set(HttpHeaders.authorizationHeader, auth);
    if (body != null) {
      final data = utf8.encode(body);
      req.headers.contentType = ContentType.parse(contentType ?? 'text/plain');
      req.contentLength = data.length;
      req.add(data);
    }
    final res = await req.close().timeout(timeout);
    final bytes = await res.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d)).timeout(timeout);
    final challenges = res.headers[HttpHeaders.wwwAuthenticateHeader];
    return _RawResponse(res.statusCode, bytes.takeBytes(), challenges?.join(', '));
  }

  String? _authHeader(String method, Uri uri) {
    if (user.isEmpty) return null;
    final d = _digest;
    if (d == null) return 'Basic ${base64.encode(utf8.encode('$user:$password'))}';

    final realm = d['realm'] ?? '';
    final nonce = d['nonce'] ?? '';
    final qop = d['qop'];
    final opaque = d['opaque'];
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    final ha1 = _md5('$user:$realm:$password');
    final ha2 = _md5('$method:$path');

    final h = StringBuffer('Digest username="$user", realm="$realm", nonce="$nonce", uri="$path", ');
    if (qop != null) {
      _nonceCount++;
      final nc = _nonceCount.toRadixString(16).padLeft(8, '0');
      final cnonce = _randomHex();
      final response = _md5('$ha1:$nonce:$nc:$cnonce:auth:$ha2');
      h.write('qop=auth, nc=$nc, cnonce="$cnonce", response="$response"');
    } else {
      h.write('response="${_md5('$ha1:$nonce:$ha2')}"');
    }
    if (opaque != null) h.write(', opaque="$opaque"');
    h.write(', algorithm=MD5');
    return h.toString();
  }

  /// Wyciąga parametry Digest z nagłówka WWW-Authenticate. Część urządzeń wysyła naraz
  /// Basic i Digest, a Dart skleja je w jeden ciąg - wycinamy sam fragment Digest.
  static String? digestChallenge(String header) {
    final start = RegExp(r'digest\s+', caseSensitive: false).firstMatch(header);
    if (start == null) return null;
    final rest = header.substring(start.end);
    final next = RegExp(r',\s*(basic|bearer|negotiate)\b', caseSensitive: false).firstMatch(rest);
    return next == null ? rest : rest.substring(0, next.start);
  }

  static Map<String, String> parseChallenge(String s) {
    final result = <String, String>{};
    for (final m in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]*))').allMatches(s)) {
      result[m.group(1)!.toLowerCase()] = m.group(2) ?? m.group(3) ?? '';
    }
    return result;
  }

  static String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  static String _randomHex() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

class _RawResponse {
  _RawResponse(this.statusCode, this.body, this.challenge);
  final int statusCode;
  final Uint8List body;
  final String? challenge;
}

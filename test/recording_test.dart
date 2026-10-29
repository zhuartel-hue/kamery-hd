import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kamery_hd/models/camera.dart';
import 'package:kamery_hd/models/recording.dart';
import 'package:kamery_hd/services/camera_api.dart';

void main() {
  final from = DateTime(2026, 10, 24, 8, 5, 0);
  final to = DateTime(2026, 10, 24, 23, 59, 59);

  test('adres odtwarzania Hikvision', () {
    final c = Camera(host: '192.168.1.10', password: 'x', channel: 3);
    expect(c.playbackUrl(from, to),
        'rtsp://admin:x@192.168.1.10:554/Streaming/tracks/301?starttime=20261024T080500Z&endtime=20261024T235959Z');
  });

  test('adres odtwarzania Dahua', () {
    final c = Camera(brand: Brand.dahua, host: '192.168.1.20', password: 'x', channel: 2);
    expect(c.playbackUrl(from, to),
        'rtsp://admin:x@192.168.1.20:554/cam/playback?channel=2&subtype=0'
        '&starttime=2026_10_24_08_05_00&endtime=2026_10_24_23_59_59');
  });

  test('wyniki wyszukiwania Hikvision', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<CMSearchResult version="2.0" xmlns="http://www.hikvision.com/ver20/XMLSchema">
<searchID>X</searchID><responseStatus>true</responseStatus><responseStatusStrg>MORE</responseStatusStrg>
<numOfMatches>2</numOfMatches><matchList>
<searchMatchItem><sourceID>{0000}</sourceID><trackID>101</trackID>
<timeSpan><startTime>2026-10-24T00:00:00Z</startTime><endTime>2026-10-24T01:00:00Z</endTime></timeSpan>
<mediaSegmentDescriptor><contentType>video</contentType></mediaSegmentDescriptor></searchMatchItem>
<searchMatchItem><trackID>101</trackID>
<timeSpan><startTime>2026-10-24T01:00:00+01:00</startTime><endTime>2026-10-24T01:30:12+01:00</endTime></timeSpan>
</searchMatchItem></matchList></CMSearchResult>''';
    final (items, more) = CameraApi.parseHikSearch(xml);
    expect(more, isTrue);
    expect(items, [
      Recording(DateTime(2026, 10, 24, 0), DateTime(2026, 10, 24, 1)),
      Recording(DateTime(2026, 10, 24, 1), DateTime(2026, 10, 24, 1, 30, 12)),
    ]);
  });

  test('wyniki wyszukiwania Dahua', () {
    const text = 'found=2\r\n'
        'items[0].Channel=0\r\nitems[0].StartTime=2026-10-24 06:00:00\r\nitems[0].EndTime=2026-10-24 07:00:00\r\n'
        'items[0].Type=dav\r\n'
        'items[1].Channel=0\r\nitems[1].StartTime=2026-10-24 12:15:00\r\nitems[1].EndTime=2026-10-24 12:20:30\r\n'
        'items[2].StartTime=2026-10-24 12:16:00\r\nitems[2].EndTime=2026-10-24 12:16:01\r\nitems[2].Type=jpg\r\n';
    expect(CameraApi.parseDahuaFind(text), [
      Recording(DateTime(2026, 10, 24, 6), DateTime(2026, 10, 24, 7)),
      Recording(DateTime(2026, 10, 24, 12, 15), DateTime(2026, 10, 24, 12, 20, 30)),
    ]);
  });

  test('sklejanie fragmentów', () {
    DateTime t(int h, [int m = 0, int s = 0]) => DateTime(2026, 10, 24, h, m, s);
    final merged = Recording.merge([
      Recording(t(2), t(3)),
      Recording(t(0), t(1)),
      Recording(t(1, 0, 1), t(2)), // przerwa 1 s - sklejamy
      Recording(t(5), t(6)),
      Recording(t(5, 30), t(5, 45)), // w środku poprzedniego
    ]);
    expect(merged, [Recording(t(0), t(3)), Recording(t(5), t(6))]);
  });

  test('czas Dahua ze spacją jako %20 (nie „+”)', () {
    expect(CameraApi.dahuaTime(DateTime(2026, 10, 29, 7, 5, 9)), '2026-10-29%2007:05:09');
  });

  test('warianty zapytania Hikvision', () {
    final from = DateTime(2026, 10, 29), to = DateTime(2026, 10, 29, 23, 59, 59);
    final a = CameraApi.hikSearchBody('trackList', 201, from, to, 0, 'ID');
    final b = CameraApi.hikSearchBody('trackIDList', 201, from, to, 50, 'ID');
    final c = CameraApi.hikSearchBody('xmlns', 201, from, to, 0, 'ID');
    expect(a, contains('<trackList><trackID>201</trackID></trackList>'));
    expect(a, contains('<startTime>2026-10-29T00:00:00Z</startTime>'));
    expect(b, contains('<trackIDList><trackID>201</trackID></trackIDList>'));
    expect(b, contains('<searchResultPostion>50</searchResultPostion>'));
    expect(c, contains('xmlns="http://www.isapi.org/ver20/XMLSchema"'));
  });

  test('Hikvision: gdy pierwszy wariant odrzucony, aplikacja próbuje kolejnego', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      if (body.contains('<trackIDList>')) {
        req.response.write('<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList>'
            '<searchMatchItem><timeSpan><startTime>2026-10-29T08:00:00Z</startTime>'
            '<endTime>2026-10-29T09:00:00Z</endTime></timeSpan></searchMatchItem></matchList></CMSearchResult>');
      } else {
        req.response.statusCode = 400;
        req.response.write('<ResponseStatus><statusString>Invalid Content</statusString></ResponseStatus>');
      }
      await req.response.close();
    });
    final api = CameraApi(Camera(host: '127.0.0.1', httpPort: server.port, user: ''));
    final recs = await api.recordings(DateTime(2026, 10, 29));
    expect(recs, [Recording(DateTime(2026, 10, 29, 8), DateTime(2026, 10, 29, 9))]);
    expect(api.searchLog.join('\n'), contains('Invalid Content'));
    api.close();
    await server.close(force: true);
  });

  test('Hikvision: adres nagrania z wyników (playbackURI) i odtwarzanie z niego', () {
    const xml = '<CMSearchResult><responseStatusStrg>OK</responseStatusStrg><matchList><searchMatchItem>'
        '<timeSpan><startTime>2026-10-29T08:00:00Z</startTime><endTime>2026-10-29T09:00:00Z</endTime></timeSpan>'
        '<mediaSegmentDescriptor><playbackURI>rtsp://192.168.1.10/Streaming/tracks/201/?starttime=20261029T080000Z'
        '&amp;endtime=20261029T090000Z&amp;name=00000000201000000&amp;size=1048576</playbackURI>'
        '</mediaSegmentDescriptor></searchMatchItem></matchList></CMSearchResult>';
    final (items, _) = CameraApi.parseHikSearch(xml);
    expect(items.single.uri, contains('&endtime=20261029T090000Z&name='));
    final c = Camera(host: '192.168.1.10', password: 'x', channel: 2);
    final url = c.playbackUrl(DateTime(2026, 10, 29, 8, 30), DateTime(2026, 10, 29, 9), deviceUri: items.single.uri);
    // ścieżka z rejestratora (z ukośnikiem na końcu), nasze godziny, bez name/size
    expect(url, 'rtsp://admin:x@192.168.1.10:554/Streaming/tracks/201/?starttime=20261029T083000Z&endtime=20261029T090000Z');
    expect(c.playbackUrl(DateTime(2026, 10, 29, 8), DateTime(2026, 10, 29, 9), maskPassword: true), contains('admin:****@'));
  });
}

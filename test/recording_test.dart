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
}

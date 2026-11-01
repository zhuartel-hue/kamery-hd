import 'package:flutter_test/flutter_test.dart';
import 'package:kamery_hd/services/event_parser.dart';
import 'package:kamery_hd/services/port_discovery.dart';

void main() {
  test('Hikvision: osoba w strefie (AcuSense) z rejestratora', () {
    final p = HikEventParser();
    const part1 = '--boundary\r\nContent-Type: application/xml\r\n\r\n'
        '<EventNotificationAlert version="2.0"><ipAddress>192.168.1.50</ipAddress>'
        '<channelID>33</channelID><dynChannelID>2</dynChannelID><eventType>fielddetection</eventType>';
    const part2 = '<eventState>active</eventState><DetectionRegionList><DetectionRegionEntry>'
        '<regionID>1</regionID><detectionTarget>human</detectionTarget></DetectionRegionEntry>'
        '</DetectionRegionList></EventNotificationAlert>\r\n--boundary\r\n';
    expect(p.feed(part1), isEmpty);
    expect(p.feed(part2), [const PersonEvent(2, 'Osoba w strefie')]);
  });

  test('Hikvision: pomija pojazd, brak ruchu i zwykły ruch', () {
    expect(
      HikEventParser.parseAlert('<EventNotificationAlert><channelID>1</channelID><eventType>linedetection</eventType>'
          '<eventState>active</eventState><targetType>vehicle</targetType></EventNotificationAlert>'),
      isNull,
    );
    expect(
      HikEventParser.parseAlert('<EventNotificationAlert><channelID>1</channelID><eventType>videoloss</eventType>'
          '<eventState>inactive</eventState></EventNotificationAlert>'),
      isNull,
    );
    expect(
      HikEventParser.parseAlert('<EventNotificationAlert><channelID>1</channelID><eventType>VMD</eventType>'
          '<eventState>active</eventState></EventNotificationAlert>'),
      isNull,
    );
    expect(
      HikEventParser.parseAlert('<EventNotificationAlert><channelID>3</channelID><eventType>linedetection</eventType>'
          '<eventState>active</eventState></EventNotificationAlert>'),
      const PersonEvent(3, 'Przekroczenie linii'),
    );
  });

  test('Dahua: osoba w strefie, kanał od 0', () {
    final p = DahuaEventParser();
    const stream = '--myboundary\r\nContent-Type: text/plain\r\nContent-Length: 39\r\n\r\nHeartbeat\r\n'
        '--myboundary\r\nContent-Type: text/plain\r\n\r\n'
        'Code=CrossRegionDetection;action=Start;index=1;data={\n'
        '   "Object" : {\n      "ObjectType" : "Human"\n   }\n}\r\n'
        '--myboundary\r\nContent-Type: text/plain\r\n\r\n'
        'Code=CrossLineDetection;action=Start;index=0;data={ "Object" : { "ObjectType" : "Vehicle" } }\r\n'
        '--myboundary\r\n';
    expect(p.feed(stream), [const PersonEvent(2, 'Osoba w strefie')]);
  });

  test('Dahua: SMD człowiek, koniec zdarzenia pomijany', () {
    expect(DahuaEventParser.parsePart('Code=SmartMotionHuman;action=Start;index=0'), const PersonEvent(1, 'Osoba (ruch)'));
    expect(DahuaEventParser.parsePart('Code=SmartMotionHuman;action=Stop;index=0'), isNull);
    expect(DahuaEventParser.parsePart('Code=VideoMotion;action=Start;index=0'), isNull);
  });

  test('porty z ustawień Hikvision', () {
    const xml = '''<AdminAccessProtocolList>
<AdminAccessProtocol><id>1</id><enabled>true</enabled><protocol>HTTP</protocol><portNo>8080</portNo></AdminAccessProtocol>
<AdminAccessProtocol><id>2</id><enabled>true</enabled><protocol>HTTPS</protocol><portNo>443</portNo></AdminAccessProtocol>
<AdminAccessProtocol><id>3</id><enabled>true</enabled><protocol>DEV_MANAGE</protocol><portNo>8000</portNo></AdminAccessProtocol>
<AdminAccessProtocol><id>4</id><enabled>true</enabled><protocol>RTSP</protocol><portNo>10554</portNo></AdminAccessProtocol>
</AdminAccessProtocolList>''';
    expect(PortDiscovery.parseHikAdminAccess(xml, 'RTSP'), 10554);
    expect(PortDiscovery.parseHikAdminAccess(xml, 'HTTP'), 8080);
    expect(PortDiscovery.parseHikAdminAccess(xml, 'SRTP'), isNull);
  });

  test('porty z ustawień Dahua', () {
    const rtsp = 'table.RTSP.Enable=true\r\ntable.RTSP.Port=8554\r\ntable.RTSP.RTP.EndPort=40000\r\n';
    expect(PortDiscovery.parseDahuaConfigPort(rtsp, 'RTSP'), 8554);
    expect(PortDiscovery.parseDahuaConfigPort('table.Web.Port=81', 'Web'), 81);
    expect(PortDiscovery.parseDahuaConfigPort('Error', 'RTSP'), isNull);
  });
}

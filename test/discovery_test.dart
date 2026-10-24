import 'package:flutter_test/flutter_test.dart';
import 'package:kamery_hd/models/discovered_channel.dart';
import 'package:kamery_hd/services/camera_api.dart';

void main() {
  test('kanały rejestratora Hikvision', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<StreamingChannelList version="2.0" xmlns="http://www.hikvision.com/ver20/XMLSchema">
<StreamingChannel version="2.0"><id>101</id><channelName>Wjazd</channelName><enabled>true</enabled>
<Video><videoCodecType>H.264</videoCodecType></Video></StreamingChannel>
<StreamingChannel version="2.0"><id>102</id><channelName>Wjazd</channelName></StreamingChannel>
<StreamingChannel version="2.0"><id>201</id><channelName></channelName></StreamingChannel>
<StreamingChannel version="2.0"><id>301</id><channelName>Garaż</channelName></StreamingChannel>
</StreamingChannelList>''';
    expect(CameraApi.parseHikChannels(xml), const [
      DiscoveredChannel(1, 'Wjazd'),
      DiscoveredChannel(2, 'Kanał 2'),
      DiscoveredChannel(3, 'Garaż'),
    ]);
  });

  test('stan kamer Hikvision', () {
    const xml = '''<InputProxyChannelStatusList>
<InputProxyChannelStatus><id>1</id><sourceInputPortDescriptor><ipAddress>192.168.1.64</ipAddress>
</sourceInputPortDescriptor><online>true</online></InputProxyChannelStatus>
<InputProxyChannelStatus><id>2</id><online>false</online></InputProxyChannelStatus>
</InputProxyChannelStatusList>''';
    expect(CameraApi.parseHikChannelStatus(xml), {1: true, 2: false});
  });

  test('kanały rejestratora Dahua', () {
    const text = 'table.ChannelTitle[0].Name=Ogród\r\n'
        'table.ChannelTitle[1].Name=\r\n'
        'table.ChannelTitle[2].Name=Ulica\r\n';
    expect(CameraApi.parseDahuaChannelTitles(text), const [
      DiscoveredChannel(1, 'Ogród'),
      DiscoveredChannel(2, 'Kanał 2'),
      DiscoveredChannel(3, 'Ulica'),
    ]);
  });

  test('stan kamer Dahua', () {
    const text = 'states[0].channel=0\r\nstates[0].connectionState=Connected\r\n'
        'states[1].channel=1\r\nstates[1].connectionState=Unconnect\r\n'
        'states[2].channel=2\r\nstates[2].connectionState=Connected\r\n';
    expect(CameraApi.parseDahuaCameraState(text), {1: true, 2: false, 3: true});
  });
}

import 'dart:math';

enum Brand { hikvision, dahua }

/// Jedna kamera (lub kanał rejestratora NVR/DVR) Hikvision albo Dahua.
/// Cała różnica między producentami sprowadza się do adresów budowanych poniżej.
class Camera {
  Camera({
    String? id,
    this.name = '',
    this.brand = Brand.hikvision,
    this.host = '',
    this.rtspPort = 554,
    this.httpPort = 80,
    this.user = 'admin',
    this.password = '',
    this.channel = 1,
    this.mainStream = false,
  }) : id = id ?? _newId();

  final String id;
  String name;
  Brand brand;
  String host;
  int rtspPort;
  int httpPort;
  String user;
  String password;
  int channel;

  /// false = strumień pomocniczy (SD), true = główny (HD).
  bool mainStream;

  bool get isHikvision => brand == Brand.hikvision;
  String get brandLabel => isHikvision ? 'Hikvision' : 'Dahua';

  String _rtspBase({bool maskPassword = false}) {
    final pass = maskPassword ? '****' : Uri.encodeComponent(password);
    final auth = user.isEmpty ? '' : '${Uri.encodeComponent(user)}:$pass@';
    return 'rtsp://$auth$host:$rtspPort';
  }

  String rtspUrl({required bool main, bool maskPassword = false}) {
    final base = _rtspBase(maskPassword: maskPassword);
    if (isHikvision) {
      // 101 = kanał 1 główny, 102 = kanał 1 pomocniczy, 201 = kanał 2 główny...
      return '$base/Streaming/Channels/$channel${main ? '01' : '02'}';
    }
    return '$base/cam/realmonitor?channel=$channel&subtype=${main ? 0 : 1}';
  }

  /// Odtwarzanie nagrań z rejestratora (lub karty SD kamery) od [from] do [to].
  /// Oba systemy podają czas lokalny urządzenia; Hikvision dopisuje „Z” mimo to.
  String playbackUrl(DateTime from, DateTime to) {
    final base = _rtspBase();
    if (isHikvision) {
      return '$base/Streaming/tracks/${channel}01?starttime=${_hikTime(from)}&endtime=${_hikTime(to)}';
    }
    return '$base/cam/playback?channel=$channel&subtype=0'
        '&starttime=${_dahuaTime(from)}&endtime=${_dahuaTime(to)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _hikTime(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}T${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';

  static String _dahuaTime(DateTime t) =>
      '${t.year}_${_two(t.month)}_${_two(t.day)}_${_two(t.hour)}_${_two(t.minute)}_${_two(t.second)}';

  String get httpBase => 'http://$host${httpPort == 80 ? '' : ':$httpPort'}';

  String get snapshotUrl => isHikvision
      ? '$httpBase/ISAPI/Streaming/channels/${channel}01/picture'
      : '$httpBase/cgi-bin/snapshot.cgi?channel=$channel';

  String get deviceInfoUrl => isHikvision
      ? '$httpBase/ISAPI/System/deviceInfo'
      : '$httpBase/cgi-bin/magicBox.cgi?action=getSystemInfo';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand.name,
        'host': host,
        'rtspPort': rtspPort,
        'httpPort': httpPort,
        'user': user,
        'password': password,
        'channel': channel,
        'mainStream': mainStream,
      };

  factory Camera.fromJson(Map<String, dynamic> j) => Camera(
        id: j['id'] as String?,
        name: j['name'] as String? ?? '',
        brand: j['brand'] == 'dahua' ? Brand.dahua : Brand.hikvision,
        host: j['host'] as String? ?? '',
        rtspPort: j['rtspPort'] as int? ?? 554,
        httpPort: j['httpPort'] as int? ?? 80,
        user: j['user'] as String? ?? 'admin',
        password: j['password'] as String? ?? '',
        channel: j['channel'] as int? ?? 1,
        mainStream: j['mainStream'] as bool? ?? false,
      );

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

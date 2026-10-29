import 'package:shared_preferences/shared_preferences.dart';

/// Układ kamer na ekranie głównym. Wybór jest zapamiętywany na telefonie.
enum CameraLayout {
  list('Lista'),
  grid4('4 kamery'),
  grid9('9 kamer'),
  grid16('16 kamer'),
  big5('1 duża + 5 małych'),
  big3('1 duża + 3 małe');

  const CameraLayout(this.label);
  final String label;

  static const _key = 'layout';

  static Future<CameraLayout> load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_key);
    return CameraLayout.values.where((l) => l.name == name).firstOrNull ?? CameraLayout.list;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, name);
  }
}

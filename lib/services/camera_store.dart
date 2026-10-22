import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera.dart';

/// Lista kamer zapisana lokalnie na telefonie.
class CameraStore {
  static const _key = 'cameras';

  Future<List<Camera>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Camera.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> saveAll(List<Camera> cameras) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cameras.map((c) => c.toJson()).toList()));
  }

  Future<void> upsert(Camera camera) async {
    final list = await load();
    final i = list.indexWhere((c) => c.id == camera.id);
    if (i >= 0) {
      list[i] = camera;
    } else {
      list.add(camera);
    }
    await saveAll(list);
  }

  Future<void> delete(String id) async {
    final list = await load();
    list.removeWhere((c) => c.id == id);
    await saveAll(list);
  }
}

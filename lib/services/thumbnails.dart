import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/camera.dart';
import 'camera_api.dart';

/// Miniatury kamer na liście: pobierane w tle (najwyżej kilka naraz, żeby
/// nie zasypać rejestratora), trzymane w pamięci i odświeżane co minutę.
class Thumbnails {
  Thumbnails._();

  static const _maxParallel = 4;
  static const maxAge = Duration(minutes: 1);

  static final Map<String, Uint8List> _images = {};
  static final Map<String, String> _errors = {};
  static final Map<String, DateTime> _fetched = {};
  static final Set<String> _active = {};
  static final Queue<Camera> _queue = Queue();

  /// Zmienia się przy każdej nowej miniaturze - do odświeżania widoków.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Uint8List? image(String id) => _images[id];
  static String? error(String id) => _errors[id];
  static bool isLoading(String id) => _active.contains(id) || _queue.any((c) => c.id == id);

  /// Zapamiętuje klatkę pobraną gdzie indziej (np. w siatce).
  static void put(String id, Uint8List image) {
    _images[id] = image;
    _errors.remove(id);
    _fetched[id] = DateTime.now();
    changes.value++;
  }

  static void fail(String id, String message) {
    _errors[id] = message;
    _fetched[id] = DateTime.now();
    changes.value++;
  }

  static void request(Camera camera) {
    final t = _fetched[camera.id];
    if (isLoading(camera.id) || (t != null && DateTime.now().difference(t) < maxAge)) return;
    _queue.add(camera);
    _pump();
  }

  /// Wymusza ponowne pobranie przy następnym [request].
  static void invalidate() => _fetched.clear();

  static void forget(String id) {
    _images.remove(id);
    _errors.remove(id);
    _fetched.remove(id);
  }

  static void _pump() {
    while (_active.length < _maxParallel && _queue.isNotEmpty) {
      final camera = _queue.removeFirst();
      _active.add(camera.id);
      _fetch(camera);
    }
  }

  static Future<void> _fetch(Camera camera) async {
    final api = CameraApi(camera);
    try {
      _images[camera.id] = await api.snapshot();
      _errors.remove(camera.id);
    } on CameraException catch (e) {
      _errors[camera.id] = e.message;
    } finally {
      api.close();
      _active.remove(camera.id);
      _fetched[camera.id] = DateTime.now();
      changes.value++;
      _pump();
    }
  }
}

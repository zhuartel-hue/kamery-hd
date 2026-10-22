import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/camera.dart';
import '../services/camera_api.dart';
import 'live_screen.dart';

/// Wszystkie kamery naraz - odświeżane klatki JPEG, lekkie dla telefonu i sieci.
class GridScreen extends StatefulWidget {
  const GridScreen({super.key, required this.cameras});
  final List<Camera> cameras;

  @override
  State<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends State<GridScreen> {
  static const _refresh = Duration(seconds: 2);

  final Map<String, Uint8List> _frames = {};
  final Map<String, String> _errors = {};
  late final Map<String, CameraApi> _apis = {for (final c in widget.cameras) c.id: CameraApi(c)};
  bool _running = true;

  @override
  void initState() {
    super.initState();
    for (final c in widget.cameras) {
      _loop(c);
    }
  }

  @override
  void dispose() {
    _running = false;
    for (final a in _apis.values) {
      a.close();
    }
    super.dispose();
  }

  Future<void> _loop(Camera c) async {
    while (_running && mounted) {
      final started = DateTime.now();
      try {
        final frame = await _apis[c.id]!.snapshot();
        if (!mounted) return;
        setState(() {
          _frames[c.id] = frame;
          _errors.remove(c.id);
        });
      } on CameraException catch (e) {
        if (!mounted) return;
        setState(() => _errors[c.id] = e.message);
      }
      final wait = _refresh - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  Future<void> _openLive(Camera c) async {
    _running = false;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => LiveScreen(camera: c)));
    if (!mounted) return;
    _running = true;
    for (final cam in widget.cameras) {
      _loop(cam);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(title: const Text('Wszystkie kamery')),
      body: GridView.builder(
        padding: const EdgeInsets.all(2),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 3 : 2,
          childAspectRatio: 16 / 9,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: widget.cameras.length,
        itemBuilder: (_, i) {
          final c = widget.cameras[i];
          final frame = _frames[c.id];
          final error = _errors[c.id];
          return GestureDetector(
            onTap: () => _openLive(c),
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Colors.black),
              if (frame != null) Image.memory(frame, fit: BoxFit.contain, gaplessPlayback: true),
              if (frame == null && error == null)
                const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              Positioned(
                left: 0,
                bottom: 0,
                right: 0,
                child: Container(
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    error == null ? c.name : '${c.name} – $error',
                    style: TextStyle(color: error == null ? Colors.white : Colors.orange.shade200, fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

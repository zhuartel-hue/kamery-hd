import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../services/camera_api.dart';

/// Podgląd na żywo. Domyślnie RTSP (płynny obraz), awaryjnie „tryb zdjęć”, czyli
/// kolejne klatki JPEG pobierane przez HTTP.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.camera});
  final Camera camera;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const _snapshotInterval = Duration(milliseconds: 500);

  late final CameraApi _api = CameraApi(widget.camera);
  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];

  late bool _mainStream = widget.camera.mainStream;
  bool _snapshotMode = false;
  bool _muted = true;
  bool _controlsVisible = true;
  bool _loading = true;
  String? _error;
  Uint8List? _frame;
  int _snapshotGeneration = 0;
  Future<void> _ptzQueue = Future.value();

  Camera get _camera => widget.camera;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Odtwarzacz zgłasza też niegroźne ostrzeżenia (np. brak dekodowania sprzętowego,
    // po którym przechodzi na programowe) - błąd pokazujemy tylko, gdy nie ma obrazu.
    _subs.add(_player.stream.width.listen((w) {
      if (w != null && w > 0 && mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (!mounted || _snapshotMode || (_player.state.width ?? 0) > 0) return;
      setState(() {
        _loading = false;
        _error = 'Nie udało się odtworzyć RTSP. Sprawdź port RTSP i hasło '
            'albo przełącz na tryb zdjęć.\n($e)';
      });
    }));
    _player.setVolume(0);
    _startRtsp();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _snapshotGeneration++;
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _startRtsp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final native = _player.platform;
    if (native is NativePlayer) {
      // TCP jest pewniejszy przez Wi-Fi i internet; bez bufora = mniejsze opóźnienie.
      await native.setProperty('rtsp-transport', 'tcp');
      await native.setProperty('cache', 'no');
    }
    await _player.open(Media(_camera.rtspUrl(main: _mainStream)));
  }

  void _setMode(bool snapshot) {
    setState(() {
      _snapshotMode = snapshot;
      _error = null;
    });
    if (snapshot) {
      _player.stop();
      _snapshotLoop();
    } else {
      _snapshotGeneration++;
      _startRtsp();
    }
  }

  Future<void> _snapshotLoop() async {
    final generation = ++_snapshotGeneration;
    setState(() => _loading = _frame == null);
    while (mounted && generation == _snapshotGeneration) {
      final started = DateTime.now();
      try {
        final frame = await _api.snapshot();
        if (!mounted || generation != _snapshotGeneration) return;
        setState(() {
          _frame = frame;
          _loading = false;
          _error = null;
        });
      } on CameraException catch (e) {
        if (!mounted || generation != _snapshotGeneration) return;
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
      final wait = _snapshotInterval - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }

  void _ptz(PtzMove move, bool start) {
    _ptzQueue = _ptzQueue.then((_) async {
      try {
        start ? await _api.ptzStart(move) : await _api.ptzStop(move);
      } on CameraException catch (e) {
        if (start) _toast('PTZ: $e');
      }
    });
  }

  Future<void> _capture() async {
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          _toast('Brak zgody na zapis w Galerii');
          return;
        }
      }
      final bytes = await _api.snapshot();
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      await Gal.putImageBytes(bytes, name: 'kamera_$stamp');
      _toast('Zapisano w Galerii');
    } on CameraException catch (e) {
      _toast('Zrzut: $e');
    } on GalException catch (e) {
      _toast('Zrzut: ${e.type.message}');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(fit: StackFit.expand, children: [
          if (_snapshotMode)
            if (_frame != null) Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)
            else const SizedBox()
          else
            Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 12),
                  if (!_snapshotMode)
                    FilledButton(onPressed: () => _setMode(true), child: const Text('Tryb zdjęć')),
                ]),
              ),
            ),
          if (_controlsVisible) ...[
            _topBar(),
            Positioned(right: 16, bottom: 16, child: SafeArea(child: _ptzPad())),
          ],
        ]),
      ),
    );
  }

  Widget _topBar() {
    const white = TextStyle(color: Colors.white);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        color: Colors.black54,
        child: SafeArea(
          bottom: false,
          child: Row(children: [
            const BackButton(color: Colors.white),
            Expanded(
              child: Text(
                '${_camera.name}${_snapshotMode ? ' · zdjęcia' : ''}',
                style: white.copyWith(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_snapshotMode) ...[
              TextButton(
                onPressed: () {
                  setState(() => _mainStream = !_mainStream);
                  _startRtsp();
                },
                child: Text(_mainStream ? 'HD' : 'SD', style: white),
              ),
              IconButton(
                tooltip: _muted ? 'Włącz dźwięk' : 'Wycisz',
                icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                onPressed: () {
                  setState(() => _muted = !_muted);
                  _player.setVolume(_muted ? 0 : 100);
                },
              ),
            ],
            IconButton(
              tooltip: _snapshotMode ? 'Wideo' : 'Tryb zdjęć',
              icon: Icon(_snapshotMode ? Icons.videocam : Icons.photo_library_outlined, color: Colors.white),
              onPressed: () => _setMode(!_snapshotMode),
            ),
            IconButton(
              tooltip: 'Zapisz zdjęcie',
              icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
              onPressed: _capture,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _ptzPad() {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Column(children: [
        _ptzButton(Icons.zoom_in, PtzMove.zoomIn),
        const SizedBox(height: 8),
        _ptzButton(Icons.zoom_out, PtzMove.zoomOut),
      ]),
      const SizedBox(width: 16),
      Column(children: [
        _ptzButton(Icons.keyboard_arrow_up, PtzMove.up),
        Row(children: [
          _ptzButton(Icons.keyboard_arrow_left, PtzMove.left),
          const SizedBox(width: 52),
          _ptzButton(Icons.keyboard_arrow_right, PtzMove.right),
        ]),
        _ptzButton(Icons.keyboard_arrow_down, PtzMove.down),
      ]),
    ]);
  }

  Widget _ptzButton(IconData icon, PtzMove move) => _PtzButton(
        icon: icon,
        onStart: () => _ptz(move, true),
        onStop: () => _ptz(move, false),
      );
}

class _PtzButton extends StatefulWidget {
  const _PtzButton({required this.icon, required this.onStart, required this.onStop});
  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  State<_PtzButton> createState() => _PtzButtonState();
}

class _PtzButtonState extends State<_PtzButton> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
    pressed ? widget.onStart() : widget.onStop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _pressed ? const Color(0xCCE0662B) : Colors.black54,
          border: Border.all(color: Colors.white38),
        ),
        child: Icon(widget.icon, color: Colors.white, size: 30),
      ),
    );
  }
}

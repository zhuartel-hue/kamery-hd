import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../services/camera_api.dart';
import '../theme.dart';
import 'playback_screen.dart';

/// Podgląd na żywo. Domyślnie RTSP (płynny obraz), awaryjnie „tryb zdjęć”, czyli
/// kolejne klatki JPEG pobierane przez HTTP.
/// Pełny ekran kamery. Przesunięcie palcem w lewo / w prawo przełącza na
/// następną / poprzednią kamerę z listy [cameras].
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.cameras, required this.index});
  final List<Camera> cameras;
  final int index;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  late int _index = widget.index;
  int _direction = 1;

  // Pasek stanu chowamy na cały czas pełnego ekranu (także przy przełączaniu kamer),
  // a przywracamy dopiero po wyjściu.
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _go(int delta) {
    final n = widget.cameras.length;
    if (n < 2) return;
    setState(() {
      _direction = delta;
      _index = (_index + delta) % n;
      if (_index < 0) _index += n;
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.cameras[_index];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, anim) => SlideTransition(
        position: Tween<Offset>(
          begin: Offset(child.key == ValueKey(camera.id) ? _direction.toDouble() : -_direction.toDouble(), 0),
          end: Offset.zero,
        ).animate(anim),
        child: child,
      ),
      child: _LiveView(
        key: ValueKey(camera.id),
        camera: camera,
        position: widget.cameras.length > 1 ? '${_index + 1}/${widget.cameras.length}' : null,
        onNext: () => _go(1),
        onPrevious: () => _go(-1),
      ),
    );
  }
}

class _LiveView extends StatefulWidget {
  const _LiveView({super.key, required this.camera, required this.onNext, required this.onPrevious, this.position});
  final Camera camera;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// „2/6” - która to kamera z listy.
  final String? position;

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  static const _snapshotInterval = Duration(milliseconds: 500);

  late final CameraApi _api = CameraApi(widget.camera);
  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];

  late bool _mainStream = widget.camera.mainStream;
  bool _snapshotMode = false;
  bool _muted = true;
  bool _controlsVisible = true;
  bool _ptzVisible = false;
  Timer? _hideTimer;
  final TransformationController _zoom = TransformationController();
  static const _hideAfter = Duration(seconds: 4);
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
    _subs.add(
      _player.stream.width.listen((w) {
        if (w != null && w > 0 && mounted) {
          setState(() {
            _loading = false;
            _error = null;
          });
        }
      }),
    );
    _subs.add(
      _player.stream.error.listen((e) {
        if (!mounted || _snapshotMode || (_player.state.width ?? 0) > 0) return;
        setState(() {
          _loading = false;
          _error =
              'Nie udało się odtworzyć RTSP. Sprawdź port RTSP i hasło '
              'albo przełącz na tryb zdjęć.\n($e)';
        });
      }),
    );
    _player.setVolume(0);
    _startRtsp();
    _scheduleHide();
  }

  /// Pasek znika sam po kilku sekundach, żeby nie zasłaniać obrazu.
  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _zoom.dispose();
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

  Future<void> _openPlayback() async {
    _snapshotGeneration++;
    await _player.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaybackScreen(camera: _camera)));
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _snapshotMode ? _snapshotLoop() : _startRtsp();
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
        onTap: _toggleControls,
        // Podwójne stuknięcie cofa powiększenie.
        onDoubleTap: () => _zoom.value = Matrix4.identity(),
        // Przesunięcie palcem w dół zamyka podgląd (gdy obraz nie jest powiększony).
        onVerticalDragEnd: (d) {
          final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
          if (!zoomed && (d.primaryVelocity ?? 0) > 700) Navigator.of(context).maybePop();
        },
        // Przesunięcie w bok - następna / poprzednia kamera (gdy obraz nie jest powiększony).
        onHorizontalDragEnd: (d) {
          final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
          final v = d.primaryVelocity ?? 0;
          if (zoomed || v.abs() < 400) return;
          v < 0 ? widget.onNext() : widget.onPrevious();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: _zoom,
              minScale: 1,
              maxScale: 6,
              child: _snapshotMode
                  ? (_frame != null
                        ? Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)
                        : const SizedBox.expand())
                  : Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
            ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Center(
                child: Container(
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Ocean.deep.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Ocean.line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      if (!_snapshotMode)
                        FilledButton(onPressed: () => _setMode(true), child: const Text('Tryb zdjęć')),
                    ],
                  ),
                ),
              ),
            if (_camera.ptz && _ptzVisible) Positioned(right: 16, bottom: 96, child: SafeArea(child: _ptzPad())),
            // Nagrania i powrót w zasięgu kciuka - zawsze widoczne, także gdy górny pasek się schowa.
            Positioned(
              right: 20,
              bottom: 20,
              child: SafeArea(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundButton(icon: Icons.history_rounded, tooltip: 'Nagrania', onTap: _openPlayback),
                    const SizedBox(width: 14),
                    _RoundButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Wróć',
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              top: _controlsVisible ? 0 : -140,
              child: Listener(onPointerDown: (_) => _scheduleHide(), child: _topBar()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    const white = TextStyle(color: Colors.white);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Ocean.abyss.withValues(alpha: 0.75), Ocean.abyss.withValues(alpha: 0.35)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const BackButton(color: Colors.white),
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _error != null ? Ocean.coral : (_loading ? Ocean.mist : Ocean.live),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${_camera.name}${widget.position == null ? '' : '  ${widget.position}'}'
                          '${_snapshotMode ? ' · zdjęcia' : ''}',
                          style: white.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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
                ],
                if (_camera.ptz)
                  IconButton(
                    tooltip: _ptzVisible ? 'Ukryj sterowanie' : 'Steruj kamerą (PTZ)',
                    isSelected: _ptzVisible,
                    icon: const Icon(Icons.control_camera_rounded, color: Colors.white),
                    selectedIcon: const Icon(Icons.control_camera_rounded, color: Ocean.aqua),
                    onPressed: () => setState(() => _ptzVisible = !_ptzVisible),
                  ),
                IconButton(
                  tooltip: 'Nagrania',
                  icon: const Icon(Icons.history, color: Colors.white),
                  onPressed: _openPlayback,
                ),
                IconButton(
                  tooltip: 'Zapisz zdjęcie',
                  icon: const Icon(Icons.camera_alt_outlined, color: Colors.white),
                  onPressed: _capture,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) {
                    if (v == 'mode') _setMode(!_snapshotMode);
                    if (v == 'sound') {
                      setState(() => _muted = !_muted);
                      _player.setVolume(_muted ? 0 : 100);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!_snapshotMode) PopupMenuItem(value: 'sound', child: Text(_muted ? 'Włącz dźwięk' : 'Wycisz')),
                    PopupMenuItem(value: 'mode', child: Text(_snapshotMode ? 'Tryb wideo' : 'Tryb zdjęć (zapasowy)')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ptzPad() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            _ptzButton(Icons.zoom_in, PtzMove.zoomIn),
            const SizedBox(height: 8),
            _ptzButton(Icons.zoom_out, PtzMove.zoomOut),
          ],
        ),
        const SizedBox(width: 16),
        Column(
          children: [
            _ptzButton(Icons.keyboard_arrow_up, PtzMove.up),
            Row(
              children: [
                _ptzButton(Icons.keyboard_arrow_left, PtzMove.left),
                const SizedBox(width: 52),
                _ptzButton(Icons.keyboard_arrow_right, PtzMove.right),
              ],
            ),
            _ptzButton(Icons.keyboard_arrow_down, PtzMove.down),
          ],
        ),
      ],
    );
  }

  Widget _ptzButton(IconData icon, PtzMove move) =>
      _PtzButton(icon: icon, onStart: () => _ptz(move, true), onStop: () => _ptz(move, false));
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
          gradient: _pressed ? Ocean.gradient : null,
          color: _pressed ? null : Ocean.abyss.withValues(alpha: 0.45),
          border: Border.all(color: _pressed ? Ocean.aqua : Colors.white.withValues(alpha: 0.28)),
          boxShadow: [if (_pressed) BoxShadow(color: Ocean.aqua.withValues(alpha: 0.5), blurRadius: 16)],
        ),
        child: Icon(widget.icon, color: Colors.white, size: 30),
      ),
    );
  }
}

/// Okrągły, półprzezroczysty przycisk na obrazie kamery.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Ocean.abyss.withValues(alpha: 0.55),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.3))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 60, height: 60, child: Icon(icon, color: Colors.white, size: 30)),
        ),
      ),
    );
  }
}

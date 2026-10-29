import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../models/recording.dart';
import '../services/camera_api.dart';
import '../theme.dart';

/// Odtwarzanie nagrań z rejestratora NVR/DVR (lub karty SD kamery).
/// RTSP nie pozwala przewijać w obrębie strumienia, więc każde przewinięcie
/// otwiera nowy strumień od wybranej chwili.
class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key, required this.camera});
  final Camera camera;

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  late final CameraApi _api = CameraApi(widget.camera);
  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final List<StreamSubscription<dynamic>> _subs = [];

  DateTime _day = _today();
  List<Recording>? _recordings;
  String? _searchError;
  int _searchGeneration = 0;

  /// Chwila, od której otwarto bieżący strumień; null = nic nie jest odtwarzane.
  DateTime? _start;

  /// Ostatnio otwierany adres nagrania (bez hasła) - do „Szczegółów technicznych”.
  String? _lastUrl;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _loading = false;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? get _current => _start?.add(_position);
  DateTime get _dayEnd => DateTime(_day.year, _day.month, _day.day, 23, 59, 59);

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.stream.position.listen((p) {
        if (mounted && _start != null) setState(() => _position = p);
      }),
    );
    _subs.add(
      _player.stream.playing.listen((p) {
        if (mounted) setState(() => _playing = p);
      }),
    );
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
    // Jak w podglądzie na żywo: ostrzeżenia odtwarzacza ignorujemy, gdy jest obraz.
    _subs.add(
      _player.stream.error.listen((e) {
        if (!mounted || _start == null || (_player.state.width ?? 0) > 0) return;
        setState(() {
          _loading = false;
          _error = 'Nie udało się odtworzyć nagrania.\n($e)';
        });
      }),
    );
    _search();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _api.close();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_searchGeneration;
    setState(() {
      _recordings = null;
      _searchError = null;
    });
    try {
      final found = await _api.recordings(_day);
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _recordings = found);
    } on CameraException catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _recordings = const [];
        _searchError = e.message;
      });
    }
  }

  void _setDay(DateTime day) {
    if (day.isAfter(_today())) return;
    _player.stop();
    setState(() {
      _day = day;
      _start = null;
      _position = Duration.zero;
      _error = null;
      _loading = false;
    });
    _search();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2015),
      lastDate: _today(),
    );
    if (picked != null) _setDay(picked);
  }

  Future<void> _pickTime() async {
    final current = _current ?? _recordings?.firstOrNull?.start ?? _day;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
    if (picked != null) {
      _playFrom(DateTime(_day.year, _day.month, _day.day, picked.hour, picked.minute));
    }
  }

  /// Otwiera nagranie od [time]; jeśli w tej chwili nic nie nagrano,
  /// przeskakuje do najbliższego późniejszego fragmentu.
  Future<void> _playFrom(DateTime time) async {
    var t = time.isBefore(_day) ? _day : (time.isAfter(_dayEnd) ? _dayEnd : time);
    final recs = _recordings ?? const <Recording>[];
    if (recs.isNotEmpty && !recs.any((r) => r.contains(t))) {
      final next = recs.where((r) => r.start.isAfter(t)).firstOrNull;
      if (next == null) {
        _toast('Brak nagrań po ${_hms(t)}');
        return;
      }
      t = next.start;
    }
    setState(() {
      _start = t;
      _position = Duration.zero;
      _loading = true;
      _error = null;
    });
    // Koniec przedziału: koniec znalezionego nagrania, nigdy w przyszłości -
    // część rejestratorów Hikvision odrzuca żądania sięgające poza „teraz”.
    final segment = recs.where((r) => r.contains(t)).firstOrNull;
    final now = DateTime.now();
    var end = segment?.end ?? _dayEnd;
    if (end.isAfter(now)) end = now;
    if (!end.isAfter(t)) end = t.add(const Duration(minutes: 1));
    _lastUrl = widget.camera.playbackUrl(t, end, deviceUri: segment?.uri, maskPassword: true);
    final native = _player.platform;
    if (native is NativePlayer) {
      await native.setProperty('rtsp-transport', 'tcp');
    }
    await _player.open(Media(widget.camera.playbackUrl(t, end, deviceUri: segment?.uri)));
  }

  void _shift(Duration d) {
    final c = _current;
    if (c != null) _playFrom(c.add(d));
  }

  void _togglePlay() {
    if (_start == null) {
      final first = _recordings?.firstOrNull;
      if (first != null) _playFrom(first.start);
      return;
    }
    _player.playOrPause();
  }

  /// Zapytania do rejestratora i jego odpowiedzi - do zrzutu ekranu przy zgłaszaniu problemu.
  void _showDetails() {
    final parts = [
      ..._api.searchLog,
      if (_lastUrl != null) 'Odtwarzanie:\n$_lastUrl',
      if (_error != null) 'Błąd odtwarzania:\n$_error',
    ];
    final log = parts.isEmpty ? 'Brak danych - wyszukiwanie jeszcze się nie odbyło.' : parts.join('\n\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Szczegóły techniczne'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(log, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log));
              Navigator.pop(ctx);
              _toast('Skopiowano - możesz wkleić w wiadomości');
            },
            child: const Text('Kopiuj'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zamknij')),
        ],
      ),
    );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String _hms(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)}';
  static String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _length(Duration d) {
    if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
    if (d.inMinutes > 0) return '${d.inMinutes} min';
    return '${d.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return landscape ? _buildLandscape(context) : _buildPortrait(context);
  }

  Widget _buildPortrait(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Nagrania · ${widget.camera.name}')),
      body: Column(
        children: [
          AspectRatio(aspectRatio: 16 / 9, child: _videoArea()),
          _dayBar(context),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _timeline(context, dark: false)),
          _controls(context, dark: false),
          const Divider(height: 1),
          Expanded(child: _recordingList(context)),
        ],
      ),
    );
  }

  Widget _buildLandscape(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _videoArea(),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              color: Colors.black54,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const BackButton(color: Colors.white),
                    Expanded(
                      child: Text(
                        'Nagrania · ${widget.camera.name}',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _dayBar(context, dark: true),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_timeline(context, dark: true), _controls(context, dark: true)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoArea() {
    final current = _current;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_start != null) Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
          if (_start == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _recordings == null
                      ? 'Szukanie nagrań…'
                      : _recordings!.isEmpty
                      ? (_searchError ?? 'Brak nagrań w tym dniu')
                      : 'Stuknij oś czasu albo ▶, aby odtworzyć nagranie',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          if (current != null)
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  _hms(current),
                  style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          if (_loading || (_recordings == null && _start == null)) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    TextButton.icon(
                      onPressed: _showDetails,
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('Szczegóły techniczne'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayBar(BuildContext context, {bool dark = false}) {
    final color = dark ? Colors.white : null;
    final isToday = _day == _today();
    final label = MaterialLocalizations.of(context).formatMediumDate(_day);
    return Row(
      mainAxisSize: dark ? MainAxisSize.min : MainAxisSize.max,
      children: [
        IconButton(
          tooltip: 'Poprzedni dzień',
          icon: Icon(Icons.chevron_left, color: color),
          onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
        ),
        if (dark)
          TextButton(
            onPressed: _pickDay,
            child: Text(label, style: TextStyle(color: color)),
          )
        else
          Expanded(
            child: TextButton.icon(
              onPressed: _pickDay,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(isToday ? 'Dzisiaj, $label' : label),
            ),
          ),
        IconButton(
          tooltip: 'Następny dzień',
          icon: Icon(Icons.chevron_right, color: isToday ? color?.withValues(alpha: 0.3) : color),
          onPressed: isToday ? null : () => _setDay(_day.add(const Duration(days: 1))),
        ),
      ],
    );
  }

  Widget _timeline(BuildContext context, {required bool dark}) {
    return RecordingTimeline(
      day: _day,
      recordings: _recordings ?? const [],
      current: _current,
      dark: dark,
      onSeek: _playFrom,
    );
  }

  Widget _controls(BuildContext context, {required bool dark}) {
    final color = dark ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final hasRecordings = _recordings?.isNotEmpty ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Cofnij 30 s',
          icon: Icon(Icons.replay_30, color: color),
          onPressed: _start == null ? null : () => _shift(const Duration(seconds: -30)),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          iconSize: 36,
          tooltip: _playing ? 'Pauza' : 'Odtwórz',
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: hasRecordings ? _togglePlay : null,
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Do przodu 30 s',
          icon: Icon(Icons.forward_30, color: color),
          onPressed: _start == null ? null : () => _shift(const Duration(seconds: 30)),
        ),
        const SizedBox(width: 16),
        TextButton.icon(
          onPressed: hasRecordings ? _pickTime : null,
          icon: Icon(Icons.schedule, color: hasRecordings ? color : null),
          label: Text('Godzina', style: TextStyle(color: hasRecordings ? color : null)),
        ),
      ],
    );
  }

  Widget _recordingList(BuildContext context) {
    final recs = _recordings;
    if (recs == null) return const SizedBox();
    if (recs.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _searchError ?? 'Brak nagrań w tym dniu',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Text(
            'Sprawdź:\n'
            '• czy w aplikacji wpisany jest adres REJESTRATORA (nagrania są na jego dysku), '
            'a nie samej kamery — teraz: ${widget.camera.host}\n'
            '• czy konto „${widget.camera.user}” ma w rejestratorze uprawnienie do odtwarzania\n'
            '• czy rejestrator ma dysk i włączone nagrywanie tej kamery\n'
            '• inny dzień (strzałka ◀ u góry)',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          Center(
            child: OutlinedButton.icon(
              onPressed: _showDetails,
              icon: const Icon(Icons.bug_report_outlined),
              label: const Text('Szczegóły techniczne'),
            ),
          ),
        ],
      );
    }
    final current = _current;
    return ListView.builder(
      itemCount: recs.length,
      itemBuilder: (_, i) {
        final r = recs[i];
        final active = current != null && r.contains(current);
        return ListTile(
          selected: active,
          leading: Icon(active ? Icons.play_circle : Icons.videocam_outlined),
          title: Text('${_hm(r.start)} – ${_hm(r.end)}'),
          subtitle: Text(_length(r.duration)),
          onTap: () => _playFrom(r.start),
        );
      },
    );
  }
}

/// Oś czasu doby: zaznaczone fragmenty z nagraniem, znacznik odtwarzania.
/// Stuknięcie lub przeciągnięcie wybiera chwilę do odtworzenia.
class RecordingTimeline extends StatefulWidget {
  const RecordingTimeline({
    super.key,
    required this.day,
    required this.recordings,
    required this.current,
    required this.onSeek,
    this.dark = false,
  });

  final DateTime day;
  final List<Recording> recordings;
  final DateTime? current;
  final ValueChanged<DateTime> onSeek;
  final bool dark;

  @override
  State<RecordingTimeline> createState() => _RecordingTimelineState();
}

class _RecordingTimelineState extends State<RecordingTimeline> {
  DateTime? _drag;

  DateTime _timeAt(double dx, double width) {
    final fraction = (dx / width).clamp(0.0, 1.0);
    return widget.day.add(Duration(seconds: (fraction * 86399).round()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => widget.onSeek(_timeAt(d.localPosition.dx, width)),
          onHorizontalDragUpdate: (d) => setState(() => _drag = _timeAt(d.localPosition.dx, width)),
          onHorizontalDragEnd: (_) {
            final t = _drag;
            setState(() => _drag = null);
            if (t != null) widget.onSeek(t);
          },
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: CustomPaint(
              painter: _TimelinePainter(
                day: widget.day,
                recordings: widget.recordings,
                marker: _drag ?? widget.current,
                track: widget.dark ? Colors.white24 : scheme.surfaceContainerHighest,
                segment: widget.dark ? Ocean.aqua : scheme.primary,
                text: widget.dark ? Colors.white70 : scheme.onSurfaceVariant,
                markerColor: Ocean.coral,
                dragging: _drag != null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.day,
    required this.recordings,
    required this.marker,
    required this.track,
    required this.segment,
    required this.text,
    required this.markerColor,
    required this.dragging,
  });

  final DateTime day;
  final List<Recording> recordings;
  final DateTime? marker;
  final Color track, segment, text, markerColor;
  final bool dragging;

  static const _barTop = 18.0, _barHeight = 20.0;

  double _x(DateTime t, double width) => (t.difference(day).inSeconds / 86400).clamp(0.0, 1.0) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final bar = RRect.fromRectAndRadius(Rect.fromLTWH(0, _barTop, w, _barHeight), const Radius.circular(4));
    canvas.drawRRect(bar, Paint()..color = track);

    canvas.save();
    canvas.clipRRect(bar);
    final seg = Paint()..color = segment;
    for (final r in recordings) {
      final x0 = _x(r.start, w), x1 = _x(r.end, w);
      canvas.drawRect(Rect.fromLTRB(x0, _barTop, (x1 - x0) < 1.5 ? x0 + 1.5 : x1, _barTop + _barHeight), seg);
    }
    canvas.restore();

    final tick = Paint()
      ..color = text.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final x = w * h / 24;
      final major = h % 3 == 0;
      canvas.drawLine(Offset(x, _barTop + _barHeight), Offset(x, _barTop + _barHeight + (major ? 7 : 4)), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$h',
            style: TextStyle(color: text, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = (x - tp.width / 2).clamp(0.0, max(0.0, w - tp.width)).toDouble();
        tp.paint(canvas, Offset(lx, _barTop + _barHeight + 9));
      }
    }

    final m = marker;
    if (m != null) {
      final x = _x(m, w);
      final p = Paint()
        ..color = markerColor
        ..strokeWidth = 2.5;
      canvas.drawLine(Offset(x, _barTop - 4), Offset(x, _barTop + _barHeight + 4), p);
      if (dragging) {
        String two(int v) => v.toString().padLeft(2, '0');
        final tp = TextPainter(
          text: TextSpan(
            text: '${two(m.hour)}:${two(m.minute)}',
            style: TextStyle(color: markerColor, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset((x - tp.width / 2).clamp(0.0, max(0.0, w - tp.width)).toDouble(), 0));
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.recordings != recordings ||
      old.marker != marker ||
      old.day != day ||
      old.dragging != dragging ||
      old.segment != segment;
}

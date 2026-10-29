import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../services/camera_api.dart';
import '../services/camera_store.dart';
import '../services/thumbnails.dart';
import '../theme.dart';
import '../widgets/wordmark.dart';
import 'camera_edit_screen.dart';
import 'grid_screen.dart';
import 'live_screen.dart';
import 'playback_screen.dart';

/// Kamery pogrupowane według urządzenia (rejestratora): kamery z tego samego
/// adresu trafiają do jednej sekcji, pojedyncze kamery - do sekcji „Kamery”.
class _Group {
  _Group(this.title, this.subtitle, this.cameras, {this.prefix, this.isDevice = true});
  final String title;
  final bool isDevice;
  final String subtitle;
  final List<Camera> cameras;

  /// Wspólny początek nazw („Dom – ”) - na kartach pokazujemy nazwę bez niego.
  final String? prefix;

  static const separator = ' – ';

  static List<_Group> of(List<Camera> cameras) {
    final byDevice = <String, List<Camera>>{};
    for (final c in cameras) {
      byDevice.putIfAbsent('${c.brand.name}|${c.host}|${c.httpPort}', () => []).add(c);
    }
    final groups = <_Group>[];
    final singles = <Camera>[];
    for (final list in byDevice.values) {
      if (list.length < 2) {
        singles.addAll(list);
        continue;
      }
      final first = list.first;
      final prefixes = list.map((c) => c.name.contains(separator) ? c.name.split(separator).first : null).toSet();
      final prefix = prefixes.length == 1 ? prefixes.first : null;
      groups.add(
        _Group(
          prefix ?? 'Rejestrator ${first.brandLabel}',
          '${first.brandLabel} · ${first.host} · ${list.length} ${_CameraListScreenState._plural(list.length)}',
          list,
          prefix: prefix,
        ),
      );
    }
    if (singles.isNotEmpty) {
      groups.add(
        _Group(
          'Kamery',
          '${singles.length} ${_CameraListScreenState._plural(singles.length)}',
          singles,
          isDevice: false,
        ),
      );
    }
    return groups;
  }

  String displayName(Camera c) {
    final p = prefix;
    return p != null && c.name.startsWith('$p$separator') ? c.name.substring(p.length + separator.length) : c.name;
  }
}

/// Numer wersji nadawany przy budowaniu na GitHubie (--dart-define=APP_VERSION=…).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'testowa');

class CameraListScreen extends StatefulWidget {
  const CameraListScreen({super.key});

  @override
  State<CameraListScreen> createState() => _CameraListScreenState();
}

class _CameraListScreenState extends State<CameraListScreen> {
  final _store = CameraStore();
  List<Camera>? _cameras;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _store.load();
    if (mounted) setState(() => _cameras = list);
  }

  Future<void> _refresh() async {
    Thumbnails.invalidate();
    await _reload();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _confirmDelete(Camera c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usunąć kamerę?'),
        content: Text('„${c.name}” zniknie z listy. Nagrania w rejestratorze zostają.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(c.id);
      Thumbnails.forget(c.id);
      _reload();
    }
  }

  void _showOptions(Camera c) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(c.name, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              _sheetItem(ctx, Icons.play_circle_outline, 'Podgląd na żywo', () => _open(LiveScreen(camera: c))),
              _sheetItem(ctx, Icons.history, 'Nagrania', () => _open(PlaybackScreen(camera: c))),
              _sheetItem(ctx, Icons.tune, 'Edytuj', () => _open(CameraEditScreen(camera: c))),
              _sheetItem(ctx, Icons.delete_outline, 'Usuń', () => _confirmDelete(c), color: scheme.error),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetItem(BuildContext ctx, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameras = _cameras;
    return Scaffold(
      body: cameras == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  _header(context, cameras),
                  if (cameras.isEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: _empty(context))
                  else
                    for (final g in _Group.of(cameras)) ...[
                      SliverToBoxAdapter(child: _sectionHeader(context, g)),
                      _feed(g),
                    ],
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 40),
                      child: Text(
                        'AriView · wersja $appVersion',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _header(BuildContext context, List<Camera> cameras) {
    final scheme = Theme.of(context).colorScheme;
    final devices = _Group.of(cameras).where((g) => g.isDevice).length;
    return SliverAppBar(
      pinned: true,
      expandedHeight: 120,
      backgroundColor: scheme.surface,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 14),
        expandedTitleScale: 1.5,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AriViewWordmark(fontSize: 20),
            if (cameras.isNotEmpty)
              Text(
                '${cameras.length} ${_plural(cameras.length)}'
                '${devices > 0 ? ' · $devices ${devices == 1 ? 'rejestrator' : 'rejestratory'}' : ''}',
                style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ),
      actions: [
        if (cameras.isNotEmpty)
          IconButton.filledTonal(
            tooltip: 'Siatka',
            icon: const Icon(Icons.grid_view_rounded),
            onPressed: () => _open(GridScreen(cameras: cameras)),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 12),
          child: _GradientIconButton(
            tooltip: 'Dodaj kamerę',
            icon: Icons.add_rounded,
            onPressed: () => _open(const CameraEditScreen()),
          ),
        ),
      ],
    );
  }

  static String _plural(int n) {
    if (n == 1) return 'kamera';
    final d = n % 10, t = n % 100;
    return d >= 2 && d <= 4 && (t < 12 || t > 14) ? 'kamery' : 'kamer';
  }

  Widget _sectionHeader(BuildContext context, _Group g) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            g.title.toUpperCase(),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              g.subtitle,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feed(_Group g) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        const gap = 3.0;
        final width = constraints.crossAxisExtent;
        final columns = (width / 600).ceil().clamp(1, 3);
        final tileWidth = (width - gap * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: gap,
            mainAxisSpacing: gap,
            mainAxisExtent: tileWidth * 9 / 16,
          ),
          itemCount: g.cameras.length,
          itemBuilder: (_, i) {
            final c = g.cameras[i];
            return CameraTile(
              key: ValueKey(c.id),
              camera: c,
              name: g.displayName(c),
              onOpen: () => _open(LiveScreen(camera: c)),
              onRecordings: () => _open(PlaybackScreen(camera: c)),
              onMore: () => _showOptions(c),
            );
          },
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              gradient: Ocean.gradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Ocean.lagoon.withValues(alpha: 0.4), blurRadius: 40)],
            ),
            child: const Icon(Icons.videocam_rounded, size: 52, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text(
            'Dodaj pierwszą kamerę',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Kamery i rejestratory Hikvision oraz Dahua w jednej aplikacji. '
            'Rejestrator dodasz razem ze wszystkimi kamerami.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 240,
            child: GradientButton(
              icon: Icons.add,
              label: 'Dodaj kamerę',
              onPressed: () => _open(const CameraEditScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kafel kamery na całą szerokość, bez ramek: obraz odświeżany co kilka sekund,
/// nazwa i stan na obrazie. Stuknięcie otwiera pełny ekran.
class CameraTile extends StatefulWidget {
  const CameraTile({
    super.key,
    required this.camera,
    required this.name,
    required this.onOpen,
    required this.onRecordings,
    required this.onMore,
  });

  final Camera camera;
  final String name;
  final VoidCallback onOpen;
  final VoidCallback onRecordings;
  final VoidCallback onMore;

  @override
  State<CameraTile> createState() => _CameraTileState();
}

class _CameraTileState extends State<CameraTile> {
  static const _refresh = Duration(seconds: 2);

  late CameraApi _api = CameraApi(widget.camera);
  bool _alive = true;

  /// Wideo na żywo w kafelku (strumień SD, bez dźwięku). Dopóki nie ruszy -
  /// albo gdy się nie uda - kafel pokazuje zdjęcie odświeżane co 2 s.
  Player? _player;
  VideoController? _video;
  bool _liveReady = false;
  bool _liveFailed = false;
  DateTime? _liveStarted;
  static const _liveTimeout = Duration(seconds: 12);
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    // Lista buduje tylko kafle widoczne na ekranie (i tuż obok), więc wideo
    // i zdjęcia dotyczą wyłącznie tego, co użytkownik ogląda. Start po pierwszej
    // klatce - dopiero wtedy wolno pytać o trasę (ModalRoute).
    WidgetsBinding.instance.addPostFrameCallback((_) => _loop());
  }

  @override
  void didUpdateWidget(CameraTile old) {
    super.didUpdateWidget(old);
    if (old.camera.toJson().toString() != widget.camera.toJson().toString()) {
      _api.close();
      _api = CameraApi(widget.camera);
      _stopLive();
      _liveFailed = false;
    }
  }

  @override
  void dispose() {
    _alive = false;
    _api.close();
    _stopLive();
    super.dispose();
  }

  Future<void> _startLive() async {
    final player = Player();
    _player = player;
    _video = VideoController(player);
    _subs.add(
      player.stream.width.listen((w) {
        if (w != null && w > 0 && mounted && !_liveReady) setState(() => _liveReady = true);
      }),
    );
    // Błędów odtwarzacza nie traktujemy jako awarii: przed pierwszą klatką zgłasza też
    // niegroźne ostrzeżenia (np. brak dekodowania sprzętowego). O porażce decyduje
    // brak obrazu po [_liveTimeout] - sprawdzane w pętli.
    _liveStarted = DateTime.now();
    await player.setVolume(0);
    final native = player.platform;
    if (native is NativePlayer) {
      await native.setProperty('rtsp-transport', 'tcp');
      await native.setProperty('cache', 'no');
    }
    await player.open(Media(widget.camera.rtspUrl(main: false)));
  }

  void _stopLive() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player?.dispose();
    _player = null;
    _video = null;
    _liveReady = false;
  }

  Future<void> _loop() async {
    while (_alive && mounted) {
      final started = DateTime.now();
      if (!mounted) return;
      final visible = ModalRoute.of(context)?.isCurrent ?? true;
      if (!visible) {
        // Na wierzchu inny ekran (np. pełny ekran kamery) - zwalniamy strumień,
        // żeby nie obciążać rejestratora i telefonu.
        if (_player != null) setState(_stopLive);
      } else {
        if (_player == null && !_liveFailed) _startLive();
        final since = _liveStarted;
        if (_player != null && !_liveReady && since != null && DateTime.now().difference(since) > _liveTimeout) {
          // Wideo nie ruszyło - zostajemy przy zdjęciach odświeżanych co 2 s.
          _liveFailed = true;
          setState(_stopLive);
        }
        if (!_liveReady) {
          try {
            final frame = await _api.snapshot();
            if (_alive) Thumbnails.put(widget.camera.id, frame);
          } on CameraException catch (e) {
            if (_alive) Thumbnails.fail(widget.camera.id, e.message);
          } catch (e) {
            // np. zamknięty klient po usunięciu kafla - nie przerywamy pętli
            if (_alive) Thumbnails.fail(widget.camera.id, 'Błąd: $e');
          }
        }
      }
      final pause = visible && !_liveReady ? _refresh : const Duration(seconds: 1);
      final wait = pause - DateTime.now().difference(started);
      await Future<void>.delayed(wait > Duration.zero ? wait : const Duration(milliseconds: 300));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onOpen,
      onLongPress: widget.onMore,
      child: ValueListenableBuilder<int>(
        valueListenable: Thumbnails.changes,
        builder: (context, _, _) => _tile(context),
      ),
    );
  }

  Widget _tile(BuildContext context) {
    final camera = widget.camera;
    final image = Thumbnails.image(camera.id);
    final error = Thumbnails.error(camera.id);
    final loading = image == null && error == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Wideo na żywo leży pod spodem; zdjęcie przykrywa je, dopóki nie pojawi się
        // pierwsza klatka (bez przezroczystości - ta psuje kolory wideo).
        if (_video != null) Video(controller: _video!, controls: NoVideoControls, fit: BoxFit.cover),
        if (image != null && !_liveReady)
          Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true)
        else if (!_liveReady)
          DecoratedBox(
            decoration: const BoxDecoration(color: Ocean.deep),
            child: Center(
              child: loading
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_rounded, size: 34, color: Ocean.mist.withValues(alpha: 0.7)),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            error ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: const TextStyle(color: Ocean.mist, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        // przyciemnienie u dołu pod nazwę
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x00000000), Color(0xB3000000)],
              begin: Alignment(0, 0.15),
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 8,
          bottom: 6,
          child: Row(
            children: [
              _StatusDot(online: _liveReady || (image != null && error == null), loading: loading && !_liveReady),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
              if (camera.ptz) const _Badge(icon: Icons.threesixty_rounded),
              _OverlayButton(icon: Icons.history_rounded, tooltip: 'Nagrania', onPressed: widget.onRecordings),
              _OverlayButton(icon: Icons.more_vert_rounded, tooltip: 'Więcej', onPressed: widget.onMore),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        color: Colors.white,
        shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
      ),
      onPressed: onPressed,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Icon(icon, size: 18, color: Ocean.aqua),
  );
}

class _GradientIconButton extends StatelessWidget {
  const _GradientIconButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(gradient: Ocean.gradient),
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.online, required this.loading});
  final bool online;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = loading ? Ocean.mist : (online ? Ocean.live : Ocean.coral);
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)],
      ),
    );
  }
}

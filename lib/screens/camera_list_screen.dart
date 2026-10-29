import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../models/camera_layout.dart';
import '../services/camera_api.dart';
import '../services/camera_store.dart';
import '../services/thumbnails.dart';
import '../theme.dart';
import '../widgets/drag_swap.dart';
import '../widgets/wordmark.dart';
import 'camera_edit_screen.dart';
import 'live_screen.dart';
import 'playback_screen.dart';

/// Kamery pogrupowane według urządzenia (rejestratora): kamery z tego samego
/// adresu trafiają do jednej sekcji, pojedyncze kamery - do sekcji „Kamery”.
class _Group {
  _Group(this.key, this.title, this.subtitle, this.cameras, {this.prefix, this.isDevice = true});

  /// Identyfikator grupy (urządzenia) - przeciągać można tylko w obrębie grupy.
  final String key;
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
    for (final entry in byDevice.entries) {
      final list = entry.value;
      if (list.length < 2) {
        singles.addAll(list);
        continue;
      }
      final first = list.first;
      final prefixes = list.map((c) => c.name.contains(separator) ? c.name.split(separator).first : null).toSet();
      final prefix = prefixes.length == 1 ? prefixes.first : null;
      groups.add(
        _Group(
          entry.key,
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
          'singles',
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

  /// Układ każdego rejestratora (grupy) - wybierany osobno i zapamiętywany.
  Map<String, CameraLayout> _layouts = {};
  CameraLayout _defaultLayout = CameraLayout.list;

  CameraLayout _layoutOf(_Group g) => _layouts[g.key] ?? _defaultLayout;

  @override
  void initState() {
    super.initState();
    _reload();
    Future.wait([CameraLayout.loadAll(), CameraLayout.loadDefault()]).then((r) {
      if (!mounted) return;
      setState(() {
        _layouts = r[0] as Map<String, CameraLayout>;
        _defaultLayout = r[1] as CameraLayout;
      });
    });
  }

  void _setLayout(_Group g, CameraLayout l) {
    setState(() {
      _layouts = {..._layouts, g.key: l};
      _wallPage = 0;
    });
    if (_wallController.hasClients) _wallController.jumpToPage(0);
    CameraLayout.saveAll(_layouts);
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
    // Inne ekrany ustawiają pasek stanu po swojemu - po powrocie ustawiamy go od nowa.
    _immersive = null;
    _reload();
  }

  /// Pełny ekran kamery z możliwością przesuwania do kolejnych - w kolejności z ekranu.
  void _openLive(Camera c) {
    final ordered = [for (final g in _Group.of(_cameras ?? const [])) ...g.cameras];
    final i = ordered.indexWhere((x) => x.id == c.id);
    _open(LiveScreen(cameras: ordered, index: i < 0 ? 0 : i));
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
              _sheetItem(ctx, Icons.play_circle_outline, 'Podgląd na żywo', () => _openLive(c)),
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

  bool? _immersive;

  /// W poziomie chowamy pasek stanu telefonu, w pionie przywracamy.
  void _syncSystemBars(bool landscape) {
    if (_immersive == landscape) return;
    _immersive = landscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cameras = _cameras;
    final landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    _syncSystemBars(landscape && (cameras?.isNotEmpty ?? false));
    if (landscape && cameras != null && cameras.isNotEmpty) {
      return Scaffold(backgroundColor: Colors.black, body: _wall(cameras));
    }
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
                      _section(g),
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
    return SliverAppBar(
      pinned: true,
      backgroundColor: scheme.surface,
      titleSpacing: 20,
      title: const AriViewWordmark(fontSize: 22),
      actions: [
        IconButton.filledTonal(
          tooltip: Theme.of(context).brightness == Brightness.dark ? 'Jasny motyw' : 'Ciemny motyw',
          icon: Icon(
            Theme.of(context).brightness == Brightness.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          ),
          onPressed: ThemeController.toggle,
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
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 6),
      child: Row(
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
          // Jedna ikona - pokazuje bieżący układ; stuknięcie otwiera wybór.
          Tooltip(
            message: 'Układ kamer',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _chooseLayout(g),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: LayoutPreview(layout: _layoutOf(g), width: 30, highlight: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Okno wyboru układu z miniaturkami.
  void _chooseLayout(_Group g) {
    final scheme = Theme.of(context).colorScheme;
    final current = _layoutOf(g);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Układ kamer · ${g.title}', style: Theme.of(ctx).textTheme.titleMedium),
              ),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.95,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final l in CameraLayout.values)
                    Material(
                      color: l == current ? scheme.primaryContainer : scheme.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: l == current ? scheme.primary : Colors.transparent, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _setLayout(g, l);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Expanded(
                                child: Center(
                                  child: LayoutPreview(layout: l, width: 64, highlight: l == current),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(l.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(
                                l == CameraLayout.list ? 'jedna pod drugą' : '${l.perBlock} na ekranie',
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _gap = 2.0;

  Widget _section(_Group g) {
    final layout = _layoutOf(g);
    return layout == CameraLayout.list ? _feed(g) : _blocks(g, layout);
  }

  Widget _tileFor(_Group g, Camera c, {required bool live, bool compact = false}) {
    return DragSwap(
      key: ValueKey('drag-${c.id}'),
      id: c.id,
      group: g.key,
      // Podgląd czyta miniaturę w chwili przeciągania, a nie przy budowaniu kafla.
      preview: Builder(
        builder: (_) {
          final image = Thumbnails.image(c.id);
          return image != null
              ? Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true)
              : const ColoredBox(
                  color: Ocean.deep,
                  child: Icon(Icons.videocam_rounded, color: Ocean.mist),
                );
        },
      ),
      onSwap: _swap,
      onHold: () => _showOptions(c),
      child: CameraTile(
        key: ValueKey('${c.id}-$live-$compact'),
        camera: c,
        name: g.displayName(c),
        live: live,
        compact: compact,
        onOpen: () => _openLive(c),
        onRecordings: () => _open(PlaybackScreen(camera: c)),
        onMore: () => _showOptions(c),
      ),
    );
  }

  /// Zamienia dwie kamery miejscami i zapamiętuje nową kolejność.
  Future<void> _swap(String from, String to) async {
    final list = [...?_cameras];
    final i = list.indexWhere((c) => c.id == from), j = list.indexWhere((c) => c.id == to);
    if (i < 0 || j < 0) return;
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
    setState(() => _cameras = list);
    await _store.saveAll(list);
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
          itemBuilder: (_, i) => _tileFor(g, g.cameras[i], live: true),
        );
      },
    );
  }

  /// Kamery w blokach układu (pionowo): pola 16:9 według siatki układu.
  Widget _blocks(_Group g, CameraLayout layout) {
    final per = layout.perBlock;
    final blocks = <List<Camera?>>[
      for (var i = 0; i < g.cameras.length; i += per)
        [for (var j = i; j < i + per; j++) j < g.cameras.length ? g.cameras[j] : null],
    ];
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final cw = (width - (layout.cols - 1) * _gap) / layout.cols;
        final height = layout.rows * cw * 9 / 16 + (layout.rows - 1) * _gap;
        return SliverList.separated(
          itemCount: blocks.length,
          separatorBuilder: (_, _) => const SizedBox(height: _gap),
          itemBuilder: (_, i) => SizedBox(width: width, height: height, child: _block(g, layout, blocks[i])),
        );
      },
    );
  }

  /// Jeden blok układu wypełniający dostępne miejsce (w pionie 16:9, w poziomie cały ekran).
  Widget _block(_Group g, CameraLayout layout, List<Camera?> cams) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = (constraints.maxWidth - (layout.cols - 1) * _gap) / layout.cols;
        final ch = (constraints.maxHeight - (layout.rows - 1) * _gap) / layout.rows;
        return Stack(
          children: [
            for (var i = 0; i < layout.cells.length; i++)
              Positioned(
                left: layout.cells[i].col * (cw + _gap),
                top: layout.cells[i].row * (ch + _gap),
                width: layout.cells[i].w * cw + (layout.cells[i].w - 1) * _gap,
                height: layout.cells[i].h * ch + (layout.cells[i].h - 1) * _gap,
                child: cams[i] == null
                    ? const ColoredBox(color: Colors.black)
                    : _tileFor(g, cams[i]!, live: layout.liveAt(i), compact: layout != CameraLayout.list),
              ),
          ],
        );
      },
    );
  }

  // ---- Telefon w poziomie: układ każdego rejestratora na cały ekran, strony przesuwane palcem ----

  int _wallPage = 0;
  final PageController _wallController = PageController();

  @override
  void dispose() {
    _wallController.dispose();
    super.dispose();
  }

  Widget _wall(List<Camera> cameras) {
    // Strony kolejnych rejestratorów, każdy w swoim układzie.
    final pages = <Widget>[];
    for (final g in _Group.of(cameras)) {
      final layout = _layoutOf(g);
      final per = layout.perBlock;
      for (var i = 0; i < g.cameras.length; i += per) {
        final cams = [for (var j = i; j < i + per; j++) j < g.cameras.length ? g.cameras[j] : null];
        pages.add(
          layout == CameraLayout.list ? _tileFor(g, cams[0]!, live: true, compact: true) : _block(g, layout, cams),
        );
      }
    }
    final current = _wallPage.clamp(0, pages.length - 1);
    return Stack(
      children: [
        PageView(controller: _wallController, onPageChanged: (i) => setState(() => _wallPage = i), children: pages),
        if (pages.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    Container(
                      width: i == current ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == current ? Ocean.aqua : Colors.white54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
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
    this.live = true,
    this.compact = false,
  });

  final Camera camera;
  final String name;

  /// false = tylko zdjęcia odświeżane co 2 s (małe kafle w siatkach 9 i 16).
  final bool live;

  /// Mały kafel: mniejszy napis, bez przycisków (dostępne po przytrzymaniu).
  final bool compact;
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
        if (widget.live && _player == null && !_liveFailed) _startLive();
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
                        if (!widget.compact) const SizedBox(height: 6),
                        if (!widget.compact)
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
          left: widget.compact ? 6 : 14,
          right: widget.compact ? 4 : 8,
          bottom: widget.compact ? 3 : 6,
          child: Row(
            children: [
              _StatusDot(online: _liveReady || (image != null && error == null), loading: loading && !_liveReady),
              SizedBox(width: widget.compact ? 5 : 8),
              Expanded(
                child: Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 11 : 16,
                    fontWeight: FontWeight.w700,
                    shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
              if (!widget.compact) ...[
                if (camera.ptz) const _Badge(icon: Icons.threesixty_rounded),
                _OverlayButton(icon: Icons.history_rounded, tooltip: 'Nagrania', onPressed: widget.onRecordings),
                _OverlayButton(icon: Icons.more_vert_rounded, tooltip: 'Więcej', onPressed: widget.onMore),
              ],
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

/// Miniaturka układu (prostokąty pól) - na ikonie i w oknie wyboru.
class LayoutPreview extends StatelessWidget {
  const LayoutPreview({super.key, required this.layout, required this.width, this.highlight = false});
  final CameraLayout layout;
  final double width;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final big = highlight ? Ocean.aqua : scheme.onSurfaceVariant;
    final small = big.withValues(alpha: 0.55);
    if (layout == CameraLayout.list) {
      final h = width * 9 / 16 * 0.42;
      return SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                height: h,
                margin: EdgeInsets.only(bottom: i < 2 ? 2 : 0),
                decoration: BoxDecoration(color: i == 0 ? big : small, borderRadius: BorderRadius.circular(2)),
              ),
          ],
        ),
      );
    }
    const gap = 2.0;
    final cw = (width - (layout.cols - 1) * gap) / layout.cols;
    final ch = cw * 9 / 16;
    return SizedBox(
      width: width,
      height: layout.rows * ch + (layout.rows - 1) * gap,
      child: Stack(
        children: [
          for (final c in layout.cells)
            Positioned(
              left: c.col * (cw + gap),
              top: c.row * (ch + gap),
              width: c.w * cw + (c.w - 1) * gap,
              height: c.h * ch + (c.h - 1) * gap,
              child: DecoratedBox(
                decoration: BoxDecoration(color: c.big ? big : small, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ],
      ),
    );
  }
}

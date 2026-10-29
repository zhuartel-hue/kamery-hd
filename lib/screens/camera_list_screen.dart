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
  CameraLayout _layout = CameraLayout.list;

  @override
  void initState() {
    super.initState();
    _reload();
    CameraLayout.load().then((l) {
      if (mounted) setState(() => _layout = l);
    });
  }

  void _setLayout(CameraLayout l) {
    setState(() {
      _layout = l;
      _wallPage = 0;
    });
    if (_wallController.hasClients) _wallController.jumpToPage(0);
    l.save();
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
                  else ...[
                    SliverToBoxAdapter(child: _layoutPicker(context)),
                    for (final g in _Group.of(cameras)) ...[
                      SliverToBoxAdapter(child: _sectionHeader(context, g)),
                      _section(g),
                    ],
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

  static const _layoutIcons = {
    CameraLayout.list: Icons.view_agenda_rounded,
    CameraLayout.grid4: Icons.grid_view_rounded,
    CameraLayout.grid9: Icons.apps_rounded,
    CameraLayout.grid16: Icons.grid_on_rounded,
    CameraLayout.big5: Icons.dashboard_rounded,
    CameraLayout.big3: Icons.view_quilt_rounded,
  };

  /// Pasek wyboru układu - zaznaczony ma turkusowe tło.
  Widget _layoutPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        children: [
          for (final l in CameraLayout.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: l.label,
                child: Material(
                  color: l == _layout ? null : scheme.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(gradient: l == _layout ? Ocean.gradient : null),
                    child: InkWell(
                      onTap: () => _setLayout(l),
                      child: SizedBox(
                        width: 52,
                        child: Icon(
                          _layoutIcons[l],
                          size: 22,
                          color: l == _layout ? Colors.white : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(_Group g) {
    return switch (_layout) {
      CameraLayout.list => _feed(g),
      CameraLayout.grid4 => _grid(g, 2, live: true),
      CameraLayout.grid9 => _grid(g, 3, live: false),
      CameraLayout.grid16 => _grid(g, 4, live: false),
      CameraLayout.big5 => _featured(g, 6, _big5),
      CameraLayout.big3 => _featured(g, 4, _big3),
    };
  }

  static const _gap = 2.0;

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
        key: ValueKey('${c.id}-${_layout.name}-$live'),
        camera: c,
        name: g.displayName(c),
        live: live,
        compact: compact,
        onOpen: () => _open(LiveScreen(camera: c)),
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

  /// Siatka 2×2, 3×3 lub 4×4. Przy 9 i 16 kamerach - zdjęcia zamiast wideo,
  /// żeby nie obciążać telefonu i rejestratora kilkunastoma strumieniami.
  Widget _grid(_Group g, int columns, {required bool live}) {
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _gap,
        mainAxisSpacing: _gap,
        childAspectRatio: 16 / 9,
      ),
      itemCount: g.cameras.length,
      itemBuilder: (_, i) => _tileFor(g, g.cameras[i], live: live, compact: true),
    );
  }

  /// Układy z jedną dużą kamerą: kamery idą blokami po [perBlock].
  Widget _featured(_Group g, int perBlock, Widget Function(_Group, List<Camera?>, double) block) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final blocks = <List<Camera?>>[];
        for (var i = 0; i < g.cameras.length; i += perBlock) {
          blocks.add([for (var j = i; j < i + perBlock; j++) j < g.cameras.length ? g.cameras[j] : null]);
        }
        return SliverList.separated(
          itemCount: blocks.length,
          separatorBuilder: (_, _) => const SizedBox(height: _gap),
          itemBuilder: (_, i) => block(g, blocks[i], width),
        );
      },
    );
  }

  Widget _cell(_Group g, Camera? c, double w, double h, {required bool big}) {
    return SizedBox(
      width: w,
      height: h,
      child: c == null ? const ColoredBox(color: Colors.black) : _tileFor(g, c, live: big, compact: !big),
    );
  }

  /// 1 duża (2×2 pola) + 5 małych dookoła - klasyczny układ rejestratorów.
  Widget _big5(_Group g, List<Camera?> c, double width) {
    final cw = (width - 2 * _gap) / 3, ch = cw * 9 / 16;
    final bw = 2 * cw + _gap, bh = 2 * ch + _gap;
    return Column(
      children: [
        Row(
          children: [
            _cell(g, c[0], bw, bh, big: true),
            const SizedBox(width: _gap),
            Column(
              children: [
                _cell(g, c[1], cw, ch, big: false),
                const SizedBox(height: _gap),
                _cell(g, c[2], cw, ch, big: false),
              ],
            ),
          ],
        ),
        const SizedBox(height: _gap),
        Row(
          children: [
            _cell(g, c[3], cw, ch, big: false),
            const SizedBox(width: _gap),
            _cell(g, c[4], cw, ch, big: false),
            const SizedBox(width: _gap),
            _cell(g, c[5], cw, ch, big: false),
          ],
        ),
      ],
    );
  }

  /// 1 duża na całą szerokość + 3 małe pod nią.
  Widget _big3(_Group g, List<Camera?> c, double width) {
    final cw = (width - 2 * _gap) / 3;
    return Column(
      children: [
        _cell(g, c[0], width, width * 9 / 16, big: true),
        const SizedBox(height: _gap),
        Row(
          children: [
            _cell(g, c[1], cw, cw * 9 / 16, big: false),
            const SizedBox(width: _gap),
            _cell(g, c[2], cw, cw * 9 / 16, big: false),
            const SizedBox(width: _gap),
            _cell(g, c[3], cw, cw * 9 / 16, big: false),
          ],
        ),
      ],
    );
  }

  // ---- Telefon w poziomie: wybrany układ na cały ekran, strony przesuwane palcem ----

  static int _perPage(CameraLayout l) => switch (l) {
    CameraLayout.list => 1,
    CameraLayout.grid4 => 4,
    CameraLayout.grid9 => 9,
    CameraLayout.grid16 => 16,
    CameraLayout.big5 => 6,
    CameraLayout.big3 => 4,
  };

  int _wallPage = 0;
  final PageController _wallController = PageController();

  @override
  void dispose() {
    _wallController.dispose();
    super.dispose();
  }

  Widget _wall(List<Camera> cameras) {
    final groups = _Group.of(cameras);
    final ordered = [for (final g in groups) ...g.cameras];
    final groupOf = {
      for (final g in groups)
        for (final c in g.cameras) c.id: g,
    };
    final per = _perPage(_layout);
    final pages = <List<Camera?>>[];
    for (var i = 0; i < ordered.length; i += per) {
      pages.add([for (var j = i; j < i + per; j++) j < ordered.length ? ordered[j] : null]);
    }
    Widget cell(Camera? c, {required bool big}) =>
        c == null ? const ColoredBox(color: Colors.black) : _tileFor(groupOf[c.id]!, c, live: big, compact: true);

    Widget page(List<Camera?> p) {
      const gap = _gap;
      switch (_layout) {
        case CameraLayout.list:
          return cell(p[0], big: true);
        case CameraLayout.grid4:
        case CameraLayout.grid9:
        case CameraLayout.grid16:
          final n = _layout == CameraLayout.grid4 ? 2 : (_layout == CameraLayout.grid9 ? 3 : 4);
          return Column(
            children: [
              for (var r = 0; r < n; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      for (var k = 0; k < n; k++) ...[
                        if (k > 0) const SizedBox(width: gap),
                        Expanded(child: cell(p[r * n + k], big: n == 2)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        case CameraLayout.big5:
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Expanded(flex: 2, child: cell(p[0], big: true)),
                    const SizedBox(width: gap),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: cell(p[1], big: false)),
                          const SizedBox(height: gap),
                          Expanded(child: cell(p[2], big: false)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: cell(p[3], big: false)),
                    const SizedBox(width: gap),
                    Expanded(child: cell(p[4], big: false)),
                    const SizedBox(width: gap),
                    Expanded(child: cell(p[5], big: false)),
                  ],
                ),
              ),
            ],
          );
        case CameraLayout.big3:
          // W poziomie: duża po lewej, trzy małe w kolumnie po prawej.
          return Row(
            children: [
              Expanded(flex: 3, child: cell(p[0], big: true)),
              const SizedBox(width: gap),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: cell(p[1], big: false)),
                    const SizedBox(height: gap),
                    Expanded(child: cell(p[2], big: false)),
                    const SizedBox(height: gap),
                    Expanded(child: cell(p[3], big: false)),
                  ],
                ),
              ),
            ],
          );
      }
    }

    final current = _wallPage.clamp(0, pages.length - 1);
    return Stack(
      children: [
        PageView.builder(
          controller: _wallController,
          scrollDirection: _layout == CameraLayout.list ? Axis.vertical : Axis.horizontal,
          itemCount: pages.length,
          onPageChanged: (i) => setState(() => _wallPage = i),
          itemBuilder: (_, i) => page(pages[i]),
        ),
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

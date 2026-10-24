import 'package:flutter/material.dart';

import '../models/camera.dart';
import '../services/camera_store.dart';
import '../services/thumbnails.dart';
import '../theme.dart';
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: cameras == null || cameras.isEmpty
          ? null
          : SizedBox(
              width: 220,
              child: GradientButton(
                icon: Icons.add,
                label: 'Dodaj kamerę',
                onPressed: () => _open(const CameraEditScreen()),
              ),
            ),
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
                      _grid(g),
                    ],
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
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
            ShaderMask(
              shaderCallback: (r) => Ocean.gradient.createShader(r),
              child: const Text(
                'Kamery HD',
                style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5),
              ),
            ),
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
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Wszystkie kamery',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () => _open(GridScreen(cameras: cameras)),
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
    final isDevice = g.isDevice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isDevice ? Icons.dns_rounded : Icons.videocam_rounded, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, style: Theme.of(context).textTheme.titleMedium),
                Text(g.subtitle, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(_Group g) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          const gap = 14.0;
          final width = constraints.crossAxisExtent;
          final columns = (width / 420).ceil().clamp(1, 4);
          final cardWidth = (width - gap * (columns - 1)) / columns;
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: gap,
              mainAxisSpacing: gap,
              mainAxisExtent: cardWidth * 9 / 16 + 70,
            ),
            itemCount: g.cameras.length,
            itemBuilder: (_, i) {
              final c = g.cameras[i];
              return CameraCard(
                camera: c,
                name: g.displayName(c),
                onOpen: () => _open(LiveScreen(camera: c)),
                onRecordings: () => _open(PlaybackScreen(camera: c)),
                onMore: () => _showOptions(c),
              );
            },
          );
        },
      ),
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

/// Karta kamery: miniatura obrazu, stan, nazwa i szybkie akcje.
class CameraCard extends StatelessWidget {
  const CameraCard({
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Thumbnails.request(camera);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onMore,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ValueListenableBuilder<int>(
                valueListenable: Thumbnails.changes,
                builder: (context, _, _) => _thumbnail(context),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kanał ${camera.channel} · ${camera.mainStream ? 'HD' : 'SD'} · ${camera.host}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Nagrania',
                      icon: const Icon(Icons.history_rounded),
                      onPressed: onRecordings,
                    ),
                    IconButton(
                      tooltip: 'Więcej',
                      icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
                      onPressed: onMore,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(BuildContext context) {
    final image = Thumbnails.image(camera.id);
    final error = Thumbnails.error(camera.id);
    final loading = image == null && error == null;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          Image.memory(image, fit: BoxFit.cover, gaplessPlayback: true)
        else
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0E3A52), Color(0xFF0B2236)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: loading
                  ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Icon(Icons.videocam_off_rounded, size: 34, color: Ocean.mist.withValues(alpha: 0.7)),
            ),
          ),
        // przyciemnienie u góry pod etykiety
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x99000000), Color(0x00000000)],
              begin: Alignment.topCenter,
              end: Alignment(0, -0.2),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: _StatusPill(online: image != null && error == null, loading: loading),
        ),
        Positioned(right: 10, top: 10, child: BrandChip(hikvision: camera.isHikvision)),
        if (image != null)
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
              ),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online, required this.loading});
  final bool online;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = loading ? Ocean.mist : (online ? Ocean.live : Ocean.coral);
    final label = loading ? 'ŁĄCZENIE' : (online ? 'ONLINE' : 'OFFLINE');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

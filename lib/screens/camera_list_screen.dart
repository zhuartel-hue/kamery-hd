import 'package:flutter/material.dart';

import '../models/camera.dart';
import '../services/camera_store.dart';
import 'camera_edit_screen.dart';
import 'grid_screen.dart';
import 'live_screen.dart';

const hikColor = Color(0xFFC8102E);
const dahuaColor = Color(0xFF0064B4);

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

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _confirmDelete(Camera c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text('Usunąć kamerę „${c.name}”?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok == true) {
      await _store.delete(c.id);
      _reload();
    }
  }

  void _showOptions(Camera c) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edytuj'),
            onTap: () {
              Navigator.pop(ctx);
              _open(CameraEditScreen(camera: c));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Usuń'),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(c);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameras = _cameras;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kamery HD'),
        actions: [
          if (cameras != null && cameras.isNotEmpty)
            IconButton(
              tooltip: 'Wszystkie kamery',
              icon: const Icon(Icons.grid_view),
              onPressed: () => _open(GridScreen(cameras: cameras)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(const CameraEditScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Dodaj kamerę'),
      ),
      body: cameras == null
          ? const Center(child: CircularProgressIndicator())
          : cameras.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Brak kamer.\nDodaj pierwszą kamerę Hikvision lub Dahua.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: cameras.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = cameras[i];
                    return ListTile(
                      leading: BrandBadge(brand: c.brand),
                      title: Text(c.name),
                      subtitle: Text('${c.host} · kanał ${c.channel} · ${c.mainStream ? 'HD' : 'SD'}'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () => _open(LiveScreen(camera: c)),
                      onLongPress: () => _showOptions(c),
                    );
                  },
                ),
    );
  }
}

class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.brand});
  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final hik = brand == Brand.hikvision;
    return Container(
      width: 60,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: hik ? hikColor : dahuaColor,
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(hik ? 'HIK' : 'DAHUA',
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

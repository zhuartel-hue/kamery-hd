import 'package:flutter/material.dart';

import '../services/event_service.dart';
import 'playback_screen.dart';

/// Lista wykrytych osób (zdarzenia z kamer) i włącznik powiadomień.
class DetectionsScreen extends StatefulWidget {
  const DetectionsScreen({super.key});

  @override
  State<DetectionsScreen> createState() => _DetectionsScreenState();
}

class _DetectionsScreenState extends State<DetectionsScreen> {
  final _events = EventService.instance;

  @override
  void initState() {
    super.initState();
    _events.markRead();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String formatTime(DateTime t) =>
      '${_two(t.hour)}:${_two(t.minute)}:${_two(t.second)} · ${_two(t.day)}.${_two(t.month)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _events,
      builder: (context, _) {
        final list = _events.detections;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Wykryte osoby'),
            actions: [
              if (list.isNotEmpty)
                IconButton(
                  tooltip: 'Wyczyść listę',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: _events.clear,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text('Powiadomienia o osobie'),
                  subtitle: const Text('Zdjęcie i powiadomienie, gdy kamera wykryje człowieka'),
                  value: _events.enabled,
                  onChanged: (v) => _events.setEnabled(v),
                ),
              ),
              if (_events.enabled)
                for (final s in _events.status.values)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Text(s, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: Text(
                  'Wykrywanie robi kamera lub rejestrator. W ustawieniach urządzenia włącz '
                  '„Wykrywanie wtargnięcia” lub „Przekroczenie linii” (Dahua: IVS / SMD), '
                  'zaznacz strefę i cel „Człowiek”, a w powiązaniach zaznacz '
                  '„Powiadom centrum monitorowania”. Powiadomienia działają, gdy AriView jest otwarta.',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('Brak wykryć', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                )
              else
                for (final d in list)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
                      leading: _thumb(d, 72, 48),
                      title: Text(d.camera.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${d.kind} · ${formatTime(d.time)}'),
                      onTap: () => showDetection(context, d),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  static Widget _thumb(Detection d, double w, double h) {
    final img = d.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
        child: img == null
            ? const ColoredBox(color: Colors.black26, child: Icon(Icons.person_outline))
            : Image.memory(img, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// Okno ze zdjęciem z chwili wykrycia i przejściem do nagrań.
Future<void> showDetection(BuildContext context, Detection d) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      title: Text(d.camera.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.image != null)
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(d.image!))
          else
            const Text('Kamera nie przesłała zdjęcia.'),
          const SizedBox(height: 10),
          Text('${d.kind} · ${_DetectionsScreenState.formatTime(d.time)}'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zamknij')),
        FilledButton.icon(
          icon: const Icon(Icons.history),
          label: const Text('Nagrania'),
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaybackScreen(camera: d.camera)));
          },
        ),
      ],
    ),
  );
}

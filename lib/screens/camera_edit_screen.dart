import 'package:flutter/material.dart';

import '../models/camera.dart';
import '../services/camera_api.dart';
import '../services/camera_store.dart';

class CameraEditScreen extends StatefulWidget {
  const CameraEditScreen({super.key, this.camera});
  final Camera? camera;

  @override
  State<CameraEditScreen> createState() => _CameraEditScreenState();
}

class _CameraEditScreenState extends State<CameraEditScreen> {
  late final Camera _c = widget.camera == null
      ? Camera()
      : Camera.fromJson(widget.camera!.toJson()); // kopia - zmiany dopiero po „Zapisz”

  late final _name = TextEditingController(text: _c.name);
  late final _host = TextEditingController(text: _c.host);
  late final _rtspPort = TextEditingController(text: '${_c.rtspPort}');
  late final _httpPort = TextEditingController(text: '${_c.httpPort}');
  late final _user = TextEditingController(text: _c.user);
  late final _pass = TextEditingController(text: _c.password);
  late final _channel = TextEditingController(text: '${_c.channel}');

  bool _showPass = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  String? _hostError;

  Camera _read() {
    _c
      ..name = _name.text.trim()
      ..host = _host.text.trim().replaceFirst(RegExp(r'^[a-z]+://'), '').replaceFirst(RegExp(r'/.*$'), '')
      ..rtspPort = int.tryParse(_rtspPort.text.trim()) ?? 554
      ..httpPort = int.tryParse(_httpPort.text.trim()) ?? 80
      ..user = _user.text.trim()
      ..password = _pass.text
      ..channel = (int.tryParse(_channel.text.trim()) ?? 1).clamp(1, 256);
    return _c;
  }

  bool _validate() {
    final ok = _read().host.isNotEmpty;
    setState(() => _hostError = ok ? null : 'Podaj adres kamery');
    return ok;
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() {
      _testing = true;
      _testResult = 'Łączenie z ${_c.httpBase} …';
    });
    final api = CameraApi(_c);
    try {
      final info = await api.deviceInfo();
      _testOk = true;
      _testResult = '✓ $info';
    } on CameraException catch (e) {
      _testOk = false;
      _testResult = '✗ $e';
    } finally {
      api.close();
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _save() async {
    if (!_validate()) return;
    if (_c.name.isEmpty) _c.name = '${_c.brandLabel} ${_c.host}';
    await CameraStore().upsert(_c);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = Camera.fromJson(_read().toJson());
    if (preview.host.isEmpty) preview.host = '<adres>';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.camera == null ? 'Nowa kamera' : widget.camera!.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<Brand>(
            segments: const [
              ButtonSegment(value: Brand.hikvision, label: Text('Hikvision')),
              ButtonSegment(value: Brand.dahua, label: Text('Dahua')),
            ],
            selected: {_c.brand},
            onSelectionChanged: (s) => setState(() => _c.brand = s.first),
          ),
          const SizedBox(height: 16),
          _field(_name, 'Nazwa', hint: 'np. Wjazd'),
          _field(_host, 'Adres IP lub domena (DDNS)',
              hint: '192.168.1.64', keyboard: TextInputType.url, error: _hostError),
          Row(children: [
            Expanded(child: _field(_rtspPort, 'Port RTSP', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: _field(_httpPort, 'Port HTTP', keyboard: TextInputType.number)),
          ]),
          _field(_user, 'Użytkownik'),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
              controller: _pass,
              obscureText: !_showPass,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Hasło',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
          ),
          _field(_channel, 'Kanał (1 dla kamery, 1…N dla rejestratora NVR/DVR)',
              keyboard: TextInputType.number),
          const Text('Strumień'),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('SD – szybki')),
              ButtonSegment(value: true, label: Text('HD – główny')),
            ],
            selected: {_c.mainStream},
            onSelectionChanged: (s) => setState(() => _c.mainStream = s.first),
          ),
          const SizedBox(height: 16),
          SelectableText(
            preview.rtspUrl(main: preview.mainStream, maskPassword: true),
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Text(_testResult!,
                style: TextStyle(
                  color: _testing ? scheme.onSurfaceVariant : (_testOk ? Colors.green.shade700 : scheme.error),
                )),
          ],
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: const Icon(Icons.network_check),
                label: const Text('Testuj'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Zapisz'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, TextInputType? keyboard, String? error}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in [_name, _host, _rtspPort, _httpPort, _user, _pass, _channel]) {
      c.dispose();
    }
    super.dispose();
  }
}

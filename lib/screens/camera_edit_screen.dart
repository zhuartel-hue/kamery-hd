import 'package:flutter/material.dart';

import '../models/camera.dart';
import '../models/discovered_channel.dart';
import '../services/camera_api.dart';
import '../services/camera_store.dart';
import '../theme.dart';

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
  bool _discovering = false;
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
      _c.ptz = await api.detectPtz();
      _testOk = true;
      _testResult = '✓ $info${_c.ptz ? ' · kamera obrotowa (PTZ)' : ''}';
    } on CameraException catch (e) {
      _testOk = false;
      _testResult = '✗ $e';
    } finally {
      api.close();
    }
    if (mounted) setState(() => _testing = false);
  }

  /// Pyta rejestrator o kanały i dodaje wybrane kamery naraz.
  Future<void> _discover() async {
    if (!_validate()) return;
    setState(() {
      _discovering = true;
      _testResult = 'Szukanie kamer w ${_c.httpBase} …';
    });
    final api = CameraApi(_c);
    final List<DiscoveredChannel> found;
    try {
      found = await api.discoverChannels();
    } on CameraException catch (e) {
      if (mounted) {
        setState(() {
          _discovering = false;
          _testOk = false;
          _testResult = '✗ $e';
        });
      }
      return;
    } finally {
      api.close();
    }
    if (!mounted) return;
    setState(() => _discovering = false);
    if (found.length <= 1) {
      setState(() {
        _testOk = true;
        _testResult = '✓ To pojedyncza kamera (1 kanał) – wystarczy ją zapisać';
        _testing = false;
      });
      return;
    }
    setState(() => _testResult = null);

    final store = CameraStore();
    final all = await store.load();
    final existing = all.where((c) => c.host == _c.host && c.brand == _c.brand).map((c) => c.channel).toSet();
    if (!mounted) return;
    final selected = await showDialog<List<DiscoveredChannel>>(
      context: context,
      builder: (_) => _ChannelPicker(found: found, existing: existing),
    );
    if (selected == null || selected.isEmpty) return;

    final prefix = _c.name.trim();
    for (final ch in selected) {
      all.add(Camera.fromJson({..._c.toJson(), 'id': null})
        ..channel = ch.channel
        ..ptz = false
        ..name = prefix.isEmpty ? ch.name : '$prefix – ${ch.name}');
    }
    await store.saveAll(all);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Dodano kamery: ${selected.length}')));
    Navigator.pop(context);
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
    final busy = _testing || _discovering;

    return Scaffold(
      appBar: AppBar(title: Text(widget.camera == null ? 'Nowa kamera' : widget.camera!.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<Brand>(
            segments: const [
              ButtonSegment(value: Brand.hikvision, label: Text('Hikvision')),
              ButtonSegment(value: Brand.dahua, label: Text('Dahua')),
            ],
            selected: {_c.brand},
            onSelectionChanged: (s) => setState(() => _c.brand = s.first),
          ),
          _section(context, 'Urządzenie', [
            _field(_name, 'Nazwa', icon: Icons.label_outline, hint: 'np. Dom, Wjazd'),
            _field(_host, 'Adres IP lub domena (DDNS)',
                icon: Icons.router_outlined, hint: '192.168.1.64', keyboard: TextInputType.url, error: _hostError),
            Row(children: [
              Expanded(child: _field(_rtspPort, 'Port RTSP', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field(_httpPort, 'Port HTTP', keyboard: TextInputType.number)),
            ]),
          ]),
          _section(context, 'Logowanie', [
            _field(_user, 'Użytkownik', icon: Icons.person_outline),
            _field(
              _pass,
              'Hasło',
              icon: Icons.lock_outline,
              obscure: !_showPass,
              suffix: IconButton(
                icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPass = !_showPass),
              ),
            ),
          ]),
          _section(context, 'Obraz', [
            _field(_channel, 'Kanał',
                icon: Icons.numbers, keyboard: TextInputType.number, helper: '1 dla kamery, 1…N dla rejestratora'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('SD · szybki')),
                ButtonSegment(value: true, label: Text('HD · pełny')),
              ],
              selected: {_c.mainStream},
              onSelectionChanged: (s) => setState(() => _c.mainStream = s.first),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              title: const Text('Kamera obrotowa (PTZ)'),
              subtitle: const Text('Pokaż sterowanie obrotem i zoomem'),
              value: _c.ptz,
              onChanged: (v) => setState(() => _c.ptz = v),
            ),
            const SizedBox(height: 4),
            SelectableText(
              preview.rtspUrl(main: preview.mainStream, maskPassword: true),
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ]),
          if (_testResult != null) _result(context),
          const SizedBox(height: 20),
          GradientButton(
            onPressed: busy ? null : _discover,
            icon: Icons.travel_explore_rounded,
            label: _discovering ? 'Szukanie kamer…' : 'Wykryj kamery w rejestratorze',
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : _test,
                icon: const Icon(Icons.network_check_rounded),
                label: const Text('Testuj'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Zapisz'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.primary,
              )),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...children, const SizedBox(height: 12)]),
          ),
        ),
      ]),
    );
  }

  Widget _result(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _testing || _discovering ? scheme.onSurfaceVariant : (_testOk ? Ocean.live : scheme.error);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Text(_testResult!, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {IconData? icon,
      String? hint,
      String? helper,
      TextInputType? keyboard,
      String? error,
      bool obscure = false,
      Widget? suffix}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        obscureText: obscure,
        autocorrect: false,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          errorText: error,
          prefixIcon: icon == null ? null : Icon(icon, size: 20),
          suffixIcon: suffix,
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

/// Okno z kanałami znalezionymi w rejestratorze. Podłączone kamery są zaznaczone,
/// a te, które już są w aplikacji, pominięte.
class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({required this.found, required this.existing});
  final List<DiscoveredChannel> found;
  final Set<int> existing;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  late final Set<int> _checked = {
    for (final c in widget.found)
      if (c.online != false && !widget.existing.contains(c.channel)) c.channel,
  };

  Iterable<DiscoveredChannel> get _available => widget.found.where((c) => !widget.existing.contains(c.channel));

  String _status(DiscoveredChannel c) {
    if (widget.existing.contains(c.channel)) return 'już dodana';
    return switch (c.online) { true => 'podłączona', false => 'brak sygnału', null => '' };
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.found.where((c) => c.online == true).length;
    return AlertDialog(
      title: Text('Znaleziono kanałów: ${widget.found.length}'),
      contentPadding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (online > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Podłączonych kamer: $online', style: Theme.of(context).textTheme.bodySmall),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final c in widget.found)
                CheckboxListTile(
                  value: widget.existing.contains(c.channel) || _checked.contains(c.channel),
                  onChanged: widget.existing.contains(c.channel)
                      ? null
                      : (v) => setState(() => v == true ? _checked.add(c.channel) : _checked.remove(c.channel)),
                  secondary: Icon(
                    Icons.circle,
                    size: 12,
                    color: switch (c.online) {
                      true => Colors.green,
                      false => Colors.grey,
                      null => Colors.transparent,
                    },
                  ),
                  title: Text(c.name),
                  subtitle: Text(['Kanał ${c.channel}', _status(c)].where((s) => s.isNotEmpty).join(' · ')),
                ),
            ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _checked.addAll(_available.map((c) => c.channel))),
          child: const Text('Zaznacz wszystkie'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.pop(context, widget.found.where((c) => _checked.contains(c.channel)).toList()),
          child: Text('Dodaj (${_checked.length})'),
        ),
      ],
    );
  }
}

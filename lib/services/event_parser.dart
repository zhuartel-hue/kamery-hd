/// Jedno zdarzenie „osoba” odczytane ze strumienia zdarzeń kamery lub rejestratora.
class PersonEvent {
  const PersonEvent(this.channel, this.kind);

  /// Numer kanału jak w aplikacji (1…N).
  final int channel;

  /// Opis dla użytkownika, np. „Osoba w strefie”.
  final String kind;

  @override
  bool operator ==(Object other) => other is PersonEvent && other.channel == channel && other.kind == kind;

  @override
  int get hashCode => Object.hash(channel, kind);

  @override
  String toString() => 'PersonEvent($channel, $kind)';
}

/// Hikvision /ISAPI/Event/notification/alertStream - kolejne bloki XML
/// <EventNotificationAlert> (strefa, linia, ruch z filtrem „człowiek” AcuSense).
class HikEventParser {
  String _buffer = '';
  static const _maxBuffer = 512 * 1024;

  static final _block = RegExp(r'<EventNotificationAlert[\s\S]*?</EventNotificationAlert>');

  List<PersonEvent> feed(String chunk) {
    _buffer += chunk;
    final result = <PersonEvent>[];
    var consumed = 0;
    for (final m in _block.allMatches(_buffer)) {
      final e = parseAlert(m.group(0)!);
      if (e != null) result.add(e);
      consumed = m.end;
    }
    _buffer = _buffer.substring(consumed);
    // Obrazy dołączane przez niektóre modele nie mogą zapchać pamięci.
    if (_buffer.length > _maxBuffer) _buffer = _buffer.substring(_buffer.length - 4096);
    return result;
  }

  static String? _tag(String xml, String tag) =>
      RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml)?.group(1)?.trim();

  /// Zamienia jeden blok <EventNotificationAlert> na zdarzenie lub null, gdy to nie osoba.
  static PersonEvent? parseAlert(String xml) {
    final type = (_tag(xml, 'eventType') ?? '').toLowerCase();
    final state = (_tag(xml, 'eventState') ?? 'active').toLowerCase();
    if (state != 'active') return null;

    final lower = xml.toLowerCase();
    final targets = RegExp(r'<(?:detectiontarget|targettype)>([^<]*)<').allMatches(lower).map((m) => m.group(1)!.trim());
    final hasTarget = targets.isNotEmpty;
    final human = targets.any((t) => t.contains('human') || t.contains('person'));
    if (hasTarget && !human) return null; // np. sam pojazd

    final String kind;
    switch (type) {
      case 'fielddetection':
      case 'regionentrance':
        kind = human ? 'Osoba w strefie' : 'Wtargnięcie w strefę';
      case 'linedetection':
        kind = human ? 'Osoba przekroczyła linię' : 'Przekroczenie linii';
      case 'regionexiting':
        kind = human ? 'Osoba opuściła strefę' : 'Wyjście ze strefy';
      case 'vmd':
        // Zwykły ruch bez filtra „człowiek” to za dużo fałszywych alarmów (liście, cienie).
        if (!human) return null;
        kind = 'Osoba (ruch)';
      default:
        return null;
    }

    final channel = int.tryParse(_tag(xml, 'dynChannelID') ?? '') ?? int.tryParse(_tag(xml, 'channelID') ?? '') ?? 1;
    return PersonEvent(channel < 1 ? 1 : channel, kind);
  }
}

/// Dahua /cgi-bin/eventManager.cgi?action=attach - części oddzielone „--myboundary”,
/// każda z wierszem „Code=…;action=Start;index=0;data={…}”.
class DahuaEventParser {
  String _buffer = '';
  static const _maxBuffer = 512 * 1024;

  static final _separator = RegExp(r'(?:^|\r?\n)--[A-Za-z0-9_\-]+');

  List<PersonEvent> feed(String chunk) {
    _buffer += chunk;
    final parts = _buffer.split(_separator);
    // Ostatni kawałek może być niepełny - czeka na kolejne dane.
    _buffer = parts.removeLast();
    if (_buffer.length > _maxBuffer) _buffer = '';
    final result = <PersonEvent>[];
    for (final p in parts) {
      final e = parsePart(p);
      if (e != null) result.add(e);
    }
    return result;
  }

  static PersonEvent? parsePart(String part) {
    final start = part.indexOf('Code=');
    if (start < 0) return null;
    final text = part.substring(start);
    final code = RegExp(r'^Code=([^;\s]+)').firstMatch(text)?.group(1) ?? '';
    final action = RegExp(r';action=([^;\s]+)').firstMatch(text)?.group(1) ?? '';
    if (action != 'Start' && action != 'Pulse') return null;
    final index = int.tryParse(RegExp(r';index=(\d+)').firstMatch(text)?.group(1) ?? '') ?? 0;

    final types = RegExp(r'"ObjectType"\s*:\s*"([^"]*)"').allMatches(text).map((m) => m.group(1)!.toLowerCase());
    final hasTarget = types.isNotEmpty;
    final human = types.any((t) => t.contains('human') || t.contains('person'));
    if (hasTarget && !human) return null;

    final String kind;
    switch (code) {
      case 'CrossRegionDetection':
        kind = human ? 'Osoba w strefie' : 'Wtargnięcie w strefę';
      case 'CrossLineDetection':
        kind = human ? 'Osoba przekroczyła linię' : 'Przekroczenie linii';
      case 'SmartMotionHuman':
        kind = 'Osoba (ruch)';
      default:
        return null;
    }
    // W zdarzeniach Dahua kanały numerowane są od 0.
    return PersonEvent(index + 1, kind);
  }
}

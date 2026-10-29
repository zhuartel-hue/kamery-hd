/// Fragment nagrania na rejestratorze (czas lokalny urządzenia).
class Recording {
  const Recording(this.start, this.end, [this.uri]);

  final DateTime start;
  final DateTime end;

  /// Adres odtwarzania podany przez rejestrator (Hikvision: playbackURI), jeśli jest.
  final String? uri;

  Duration get duration => end.difference(start);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  /// Sortuje i skleja nachodzące na siebie lub stykające się fragmenty
  /// (rejestratory dzielą nagranie ciągłe na pliki np. co godzinę).
  static List<Recording> merge(Iterable<Recording> items, {Duration gap = const Duration(seconds: 2)}) {
    final sorted = items.where((r) => r.end.isAfter(r.start)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <Recording>[];
    for (final r in sorted) {
      if (result.isNotEmpty && !r.start.isAfter(result.last.end.add(gap))) {
        final last = result.removeLast();
        result.add(Recording(last.start, r.end.isAfter(last.end) ? r.end : last.end, last.uri ?? r.uri));
      } else {
        result.add(r);
      }
    }
    return result;
  }

  /// Parsuje czas z odpowiedzi urządzenia: „2026-10-24T08:00:00Z”, „2026-10-24 08:00:00”,
  /// także z dopiskiem strefy. Zawsze traktujemy go jako czas lokalny.
  static DateTime? parseDeviceTime(String s) {
    final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final v = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(v[0], v[1], v[2], v[3], v[4], v[5]);
  }

  @override
  bool operator ==(Object other) => other is Recording && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Recording($start – $end)';
}

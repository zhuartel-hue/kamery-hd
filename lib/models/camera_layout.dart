import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Pole układu: kolumna, wiersz, szerokość i wysokość w polach siatki.
class LayoutCell {
  const LayoutCell(this.col, this.row, [this.w = 1, this.h = 1]);
  final int col, row, w, h;
  bool get big => w > 1 || h > 1;
}

/// Układ kamer. [cols]×[rows] pól o proporcjach 16:9; [cells] to miejsca na kamery
/// w kolejności (pierwsza - zwykle duża). Lista ([list]) nie ma pól - kamery jedna pod drugą.
enum CameraLayout {
  list('Lista', 0, 0, []),
  grid4('2×2', 2, 2, _grid2),
  grid9('3×3', 3, 3, _grid3),
  grid16('4×4', 4, 4, _grid4),
  big3('1 + 3', 3, 4, [LayoutCell(0, 0, 3, 3), LayoutCell(0, 3), LayoutCell(1, 3), LayoutCell(2, 3)]),
  big5('1 + 5', 3, 3, [
    LayoutCell(0, 0, 2, 2),
    LayoutCell(2, 0),
    LayoutCell(2, 1),
    LayoutCell(0, 2),
    LayoutCell(1, 2),
    LayoutCell(2, 2),
  ]),
  big6('1 + 6', 3, 5, [
    LayoutCell(0, 0, 3, 3),
    LayoutCell(0, 3),
    LayoutCell(1, 3),
    LayoutCell(2, 3),
    LayoutCell(0, 4),
    LayoutCell(1, 4),
    LayoutCell(2, 4),
  ]),
  big7('1 + 7', 4, 4, [
    LayoutCell(0, 0, 3, 3),
    LayoutCell(3, 0),
    LayoutCell(3, 1),
    LayoutCell(3, 2),
    LayoutCell(0, 3),
    LayoutCell(1, 3),
    LayoutCell(2, 3),
    LayoutCell(3, 3),
  ]),
  big12('1 + 12', 4, 4, [
    LayoutCell(0, 0, 2, 2),
    LayoutCell(2, 0),
    LayoutCell(3, 0),
    LayoutCell(2, 1),
    LayoutCell(3, 1),
    LayoutCell(0, 2),
    LayoutCell(1, 2),
    LayoutCell(2, 2),
    LayoutCell(3, 2),
    LayoutCell(0, 3),
    LayoutCell(1, 3),
    LayoutCell(2, 3),
    LayoutCell(3, 3),
  ]);

  const CameraLayout(this.label, this.cols, this.rows, this.cells);
  final String label;
  final int cols, rows;
  final List<LayoutCell> cells;

  /// Ile kamer mieści jedna strona/blok układu.
  int get perBlock => this == list ? 1 : cells.length;

  /// Czy pole pokazuje wideo na żywo: duże pola i siatka 2×2. Małe pola - zdjęcia,
  /// żeby nie obciążać telefonu i rejestratora kilkunastoma strumieniami.
  bool liveAt(int index) => this == list || this == grid4 || cells[index].big;

  static const _key = 'layouts';
  static const _legacyKey = 'layout';

  /// Układ każdej grupy (rejestratora), zapamiętany na telefonie.
  static Future<Map<String, CameraLayout>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, CameraLayout>{};
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      raw.forEach((group, name) {
        final l = values.where((v) => v.name == name).firstOrNull;
        if (l != null) result[group] = l;
      });
    } on FormatException {
      // uszkodzony zapis - zaczynamy od domyślnych
    }
    return result;
  }

  /// Domyślny układ dla grup bez własnego wyboru (dawny wspólny wybór z wersji ≤1.0.14).
  static Future<CameraLayout> loadDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_legacyKey);
    return values.where((v) => v.name == name).firstOrNull ?? list;
  }

  static Future<void> saveAll(Map<String, CameraLayout> layouts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({for (final e in layouts.entries) e.key: e.value.name}));
  }
}

const _grid2 = [LayoutCell(0, 0), LayoutCell(1, 0), LayoutCell(0, 1), LayoutCell(1, 1)];
const _grid3 = [
  LayoutCell(0, 0),
  LayoutCell(1, 0),
  LayoutCell(2, 0),
  LayoutCell(0, 1),
  LayoutCell(1, 1),
  LayoutCell(2, 1),
  LayoutCell(0, 2),
  LayoutCell(1, 2),
  LayoutCell(2, 2),
];
const _grid4 = [
  LayoutCell(0, 0),
  LayoutCell(1, 0),
  LayoutCell(2, 0),
  LayoutCell(3, 0),
  LayoutCell(0, 1),
  LayoutCell(1, 1),
  LayoutCell(2, 1),
  LayoutCell(3, 1),
  LayoutCell(0, 2),
  LayoutCell(1, 2),
  LayoutCell(2, 2),
  LayoutCell(3, 2),
  LayoutCell(0, 3),
  LayoutCell(1, 3),
  LayoutCell(2, 3),
  LayoutCell(3, 3),
];

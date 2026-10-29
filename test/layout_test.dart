import 'package:flutter_test/flutter_test.dart';
import 'package:kamery_hd/models/camera_layout.dart';

void main() {
  test('każdy układ wypełnia swoją siatkę dokładnie raz', () {
    for (final l in CameraLayout.values.where((l) => l != CameraLayout.list)) {
      final taken = <String>{};
      for (final c in l.cells) {
        for (var x = c.col; x < c.col + c.w; x++) {
          for (var y = c.row; y < c.row + c.h; y++) {
            expect(x < l.cols && y < l.rows, isTrue, reason: '${l.name}: pole ($x,$y) poza siatką');
            expect(taken.add('$x,$y'), isTrue, reason: '${l.name}: pole ($x,$y) zajęte dwa razy');
          }
        }
      }
      expect(taken.length, l.cols * l.rows, reason: '${l.name}: puste pola w siatce');
    }
  });

  test('liczba kamer w układach', () {
    expect(CameraLayout.big6.perBlock, 7);
    expect(CameraLayout.big7.perBlock, 8);
    expect(CameraLayout.big12.perBlock, 13);
    expect(CameraLayout.grid16.perBlock, 16);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:skywrath/game/puzzle.dart';
import 'package:skywrath/services/progress.dart';

void main() {
  test('every level generates and is solvable by resetting rotations', () {
    for (var level = 1; level <= kTotalLevels; level++) {
      final p = PuzzleGenerator.generate(level);

      // Sanity: source and target exist and are conductive.
      expect(p.cells[p.sourceIndex].kind, CellKind.source, reason: 'L$level');
      expect(p.cells[p.targetIndex].kind, CellKind.target, reason: 'L$level');

      // The canonical solution is every wire at its base orientation.
      for (final c in p.cells) {
        if (c.kind == CellKind.wire) c.turns = 0;
      }
      expect(p.isSolved, isTrue,
          reason: 'Level $level must be solvable at base orientation');
    }
  });

  test('generated puzzles start unsolved', () {
    var scrambledCount = 0;
    for (var level = 1; level <= kTotalLevels; level++) {
      final p = PuzzleGenerator.generate(level);
      if (!p.isSolved) scrambledCount++;
    }
    // The vast majority should start unsolved.
    expect(scrambledCount, greaterThan(kTotalLevels - 3));
  });
}

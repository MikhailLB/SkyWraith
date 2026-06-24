import 'dart:collection';
import 'dart:math';

/// Direction bit flags.
const int kUp = 1;
const int kRight = 2;
const int kDown = 4;
const int kLeft = 8;

const List<int> kDirs = [kUp, kRight, kDown, kLeft];

/// Row / column deltas for each direction bit.
int dRow(int dir) {
  switch (dir) {
    case kUp:
      return -1;
    case kDown:
      return 1;
    default:
      return 0;
  }
}

int dCol(int dir) {
  switch (dir) {
    case kLeft:
      return -1;
    case kRight:
      return 1;
    default:
      return 0;
  }
}

int opposite(int dir) {
  switch (dir) {
    case kUp:
      return kDown;
    case kDown:
      return kUp;
    case kLeft:
      return kRight;
    case kRight:
      return kLeft;
  }
  return 0;
}

/// Rotate a connection mask 90 degrees clockwise.
int rotateCW(int mask) => ((mask << 1) | (mask >> 3)) & 0xF;

/// Apply [turns] clockwise rotations to [mask].
int rotateMask(int mask, int turns) {
  int m = mask;
  final t = ((turns % 4) + 4) % 4;
  for (var i = 0; i < t; i++) {
    m = rotateCW(m);
  }
  return m;
}

enum CellKind { empty, wire, source, target }

enum HubImage { cloud, tower, tree }

class Cell {
  Cell({
    required this.row,
    required this.col,
    required this.kind,
    this.baseConnections = 0,
    this.turns = 0,
    this.rotatable = true,
    this.hub = HubImage.cloud,
  });

  final int row;
  final int col;
  CellKind kind;

  /// Connections in the unrotated (turns == 0) state.
  int baseConnections;

  /// Number of clockwise quarter-turns applied by the player.
  int turns;
  bool rotatable;
  HubImage hub;

  /// Current connection mask taking rotation into account.
  int get connections => rotateMask(baseConnections, turns);

  bool get isConductive => kind != CellKind.empty;

  void rotate() {
    if (rotatable) turns++;
  }
}

class Puzzle {
  Puzzle({
    required this.level,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.sourceIndex,
    required this.targetIndex,
  });

  final int level;
  final int rows;
  final int cols;
  final List<Cell> cells;
  final int sourceIndex;
  final int targetIndex;

  int index(int r, int c) => r * cols + c;
  bool inside(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;
  Cell cellAt(int r, int c) => cells[index(r, c)];

  /// Computes the set of cell indices that are energised from the source.
  Set<int> computePowered() {
    final powered = <int>{};
    final queue = Queue<int>();
    powered.add(sourceIndex);
    queue.add(sourceIndex);

    while (queue.isNotEmpty) {
      final i = queue.removeFirst();
      final cell = cells[i];
      final conns = cell.connections;
      for (final dir in kDirs) {
        if (conns & dir == 0) continue;
        final nr = cell.row + dRow(dir);
        final nc = cell.col + dCol(dir);
        if (!inside(nr, nc)) continue;
        final ni = index(nr, nc);
        final neighbor = cells[ni];
        if (!neighbor.isConductive) continue;
        // Must mate: neighbor needs the opposite connection.
        if (neighbor.connections & opposite(dir) == 0) continue;
        if (powered.add(ni)) {
          queue.add(ni);
        }
      }
    }
    return powered;
  }

  bool get isSolved => computePowered().contains(targetIndex);

  /// Total rotatable pieces (used for stats / star scoring).
  int get rotatableCount => cells.where((c) => c.rotatable && c.isConductive).length;
}

class _Edges {
  final List<int> conn;
  _Edges(int n) : conn = List.filled(n, 0);
}

/// Deterministic puzzle generator. The same [level] always yields the same,
/// guaranteed-solvable puzzle.
class PuzzleGenerator {
  static ({int rows, int cols}) sizeForLevel(int level) {
    if (level <= 4) return (rows: 3, cols: 3);
    if (level <= 9) return (rows: 4, cols: 3);
    if (level <= 15) return (rows: 4, cols: 4);
    if (level <= 22) return (rows: 5, cols: 4);
    if (level <= 30) return (rows: 5, cols: 5);
    if (level <= 36) return (rows: 6, cols: 5);
    return (rows: 7, cols: 5);
  }

  static Puzzle generate(int level) {
    final rng = Random(73856093 ^ (level * 19349663));
    final size = sizeForLevel(level);
    final rows = size.rows;
    final cols = size.cols;
    final n = rows * cols;

    int idx(int r, int c) => r * cols + c;

    // 1) Build a random spanning tree with randomized DFS.
    final edges = _Edges(n);
    final visited = List.filled(n, false);
    final parent = List.filled(n, -1);

    final start = idx(0, rng.nextInt(cols));
    final stack = <int>[start];
    visited[start] = true;
    while (stack.isNotEmpty) {
      final cur = stack.last;
      final r = cur ~/ cols;
      final c = cur % cols;
      final candidates = <int>[]; // direction bits to unvisited neighbors
      for (final dir in kDirs) {
        final nr = r + dRow(dir);
        final nc = c + dCol(dir);
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        if (visited[idx(nr, nc)]) continue;
        candidates.add(dir);
      }
      if (candidates.isEmpty) {
        stack.removeLast();
        continue;
      }
      final dir = candidates[rng.nextInt(candidates.length)];
      final nr = r + dRow(dir);
      final nc = c + dCol(dir);
      final ni = idx(nr, nc);
      edges.conn[cur] |= dir;
      edges.conn[ni] |= opposite(dir);
      visited[ni] = true;
      parent[ni] = cur;
      stack.add(ni);
    }

    // 2) Choose source (top region) and target (bottom region) far apart.
    final sourceIndex = idx(0, rng.nextInt(cols));
    final targetIndex = idx(rows - 1, rng.nextInt(cols));

    // 3) Determine the solution path between source and target (in the tree)
    //    so we never prune those cells.
    final onPath = _pathCells(sourceIndex, targetIndex, edges.conn, rows, cols);

    // 4) Prune some leaves into empty cells for variety. Early levels prune
    //    more aggressively (smaller, simpler boards); later levels stay full.
    final pruneChance = (0.55 - level * 0.012).clamp(0.05, 0.55);
    final degree = List<int>.generate(n, (i) => _popcount(edges.conn[i]));
    bool changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < n; i++) {
        if (edges.conn[i] == 0) continue;
        if (i == sourceIndex || i == targetIndex || onPath.contains(i)) continue;
        if (degree[i] != 1) continue;
        if (rng.nextDouble() > pruneChance) continue;
        // Remove this leaf and detach it from its parent.
        final dir = edges.conn[i];
        edges.conn[i] = 0;
        final r = i ~/ cols;
        final c = i % cols;
        final nr = r + dRow(dir);
        final nc = c + dCol(dir);
        if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
          final ni = idx(nr, nc);
          edges.conn[ni] &= ~opposite(dir);
          degree[ni] = _popcount(edges.conn[ni]);
        }
        degree[i] = 0;
        changed = true;
      }
    }

    // 5) Build the cells.
    final cells = <Cell>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final i = idx(r, c);
        final mask = edges.conn[i];
        CellKind kind;
        bool rotatable;
        if (i == sourceIndex) {
          kind = CellKind.source;
          rotatable = false;
        } else if (i == targetIndex) {
          kind = CellKind.target;
          rotatable = false;
        } else if (mask == 0) {
          kind = CellKind.empty;
          rotatable = false;
        } else {
          kind = CellKind.wire;
          rotatable = true;
        }
        cells.add(Cell(
          row: r,
          col: c,
          kind: kind,
          baseConnections: mask,
          rotatable: rotatable,
          hub: _hubFor(mask, rng),
        ));
      }
    }

    // 6) Lock a few helper pieces in the correct orientation on early levels.
    final fixedFraction = level <= 3
        ? 0.30
        : level <= 8
            ? 0.18
            : level <= 14
                ? 0.08
                : 0.0;
    if (fixedFraction > 0) {
      final wireIdx = <int>[
        for (var i = 0; i < n; i++)
          if (cells[i].kind == CellKind.wire) i
      ]..shuffle(rng);
      final lockCount = (wireIdx.length * fixedFraction).round();
      for (var k = 0; k < lockCount; k++) {
        cells[wireIdx[k]].rotatable = false;
      }
    }

    // 7) Scramble rotation of every rotatable wire.
    for (final cell in cells) {
      if (cell.kind == CellKind.wire && cell.rotatable) {
        cell.turns = rng.nextInt(4);
      }
    }

    final puzzle = Puzzle(
      level: level,
      rows: rows,
      cols: cols,
      cells: cells,
      sourceIndex: sourceIndex,
      targetIndex: targetIndex,
    );

    // 8) Make sure it is not accidentally already solved.
    if (puzzle.isSolved) {
      final firstRotatable = cells.firstWhere(
        (c) => c.kind == CellKind.wire && c.rotatable,
        orElse: () => cells[sourceIndex],
      );
      if (firstRotatable.kind == CellKind.wire) {
        firstRotatable.turns += 1;
        // If a single turn keeps a symmetric piece solved, nudge again.
        if (puzzle.isSolved) firstRotatable.turns += 1;
      }
    }

    return puzzle;
  }

  static Set<int> _pathCells(
      int from, int to, List<int> conn, int rows, int cols) {
    int idx(int r, int c) => r * cols + c;
    final n = rows * cols;
    final prev = List.filled(n, -1);
    final visited = List.filled(n, false);
    final queue = Queue<int>()..add(from);
    visited[from] = true;
    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      if (cur == to) break;
      final r = cur ~/ cols;
      final c = cur % cols;
      for (final dir in kDirs) {
        if (conn[cur] & dir == 0) continue;
        final nr = r + dRow(dir);
        final nc = c + dCol(dir);
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        final ni = idx(nr, nc);
        if (visited[ni]) continue;
        visited[ni] = true;
        prev[ni] = cur;
        queue.add(ni);
      }
    }
    final path = <int>{};
    var cur = to;
    while (cur != -1) {
      path.add(cur);
      if (cur == from) break;
      cur = prev[cur];
    }
    return path;
  }

  static int _popcount(int x) {
    int count = 0;
    while (x != 0) {
      count += x & 1;
      x >>= 1;
    }
    return count;
  }

  static HubImage _hubFor(int mask, Random rng) {
    final deg = _popcount(mask);
    if (deg >= 3) return HubImage.tower;
    if (deg == 2) {
      // Corner pieces sometimes use the tree tile for variety.
      final isStraight = mask == (kUp | kDown) || mask == (kLeft | kRight);
      if (!isStraight && rng.nextBool()) return HubImage.tree;
    }
    return HubImage.cloud;
  }
}

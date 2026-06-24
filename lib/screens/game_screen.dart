import 'dart:math';
import 'package:flutter/material.dart';

import '../game/puzzle.dart';
import '../services/progress.dart';
import '../theme.dart';
import '../widgets/piece_painter.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.level,
    required this.progress,
  });

  final int level;
  final Progress progress;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  late Puzzle _puzzle;
  late int _level;
  Set<int> _powered = {};
  int _moves = 0;
  bool _solved = false;

  late final AnimationController _pulseCtrl;
  late final AnimationController _winCtrl;

  @override
  void initState() {
    super.initState();
    _level = widget.level;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _winCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadLevel(_level);
  }

  void _loadLevel(int level) {
    _puzzle = PuzzleGenerator.generate(level);
    _powered = _puzzle.computePowered();
    _moves = 0;
    _solved = false;
    _winCtrl.reset();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _winCtrl.dispose();
    super.dispose();
  }

  void _onTapCell(Cell cell) {
    if (_solved || !cell.rotatable || cell.kind != CellKind.wire) return;
    setState(() {
      cell.rotate();
      _moves++;
      _powered = _puzzle.computePowered();
      if (_powered.contains(_puzzle.targetIndex)) {
        _onSolved();
      }
    });
  }

  Future<void> _onSolved() async {
    _solved = true;
    _winCtrl.forward(from: 0);
    await widget.progress.markCompleted(_level);
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) _showWinSheet();
  }

  void _showWinSheet() {
    final hasNext = _level < kTotalLevels;
    final stars = _starsForMoves();
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WinSheet(
        level: _level,
        moves: _moves,
        stars: stars,
        hasNext: hasNext,
        onReplay: () {
          Navigator.pop(ctx);
          setState(() => _loadLevel(_level));
        },
        onNext: hasNext
            ? () {
                Navigator.pop(ctx);
                setState(() {
                  _level++;
                  _loadLevel(_level);
                });
              }
            : null,
        onMenu: () {
          Navigator.pop(ctx);
          Navigator.pop(context, true);
        },
      ),
    );
  }

  int _starsForMoves() {
    final ideal = _puzzle.rotatableCount;
    if (_moves <= ideal + (ideal * 0.4)) return 3;
    if (_moves <= ideal * 2.2) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.webp', fit: BoxFit.cover),
          Container(color: SkyColors.deepNavy.withValues(alpha: 0.45)),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(child: _board()),
                _bottomHint(),
              ],
            ),
          ),
          _winFlash(),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _circleButton(Icons.arrow_back, () => Navigator.pop(context, false)),
          const Spacer(),
          Column(
            children: [
              Text(
                'LEVEL $_level',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: SkyColors.goldBright,
                ),
              ),
              Text(
                'Moves: $_moves',
                style: const TextStyle(
                    fontSize: 13, color: SkyColors.electricSoft),
              ),
            ],
          ),
          const Spacer(),
          _circleButton(Icons.refresh,
              () => setState(() => _loadLevel(_level))),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: SkyColors.panel,
      shape: const CircleBorder(
          side: BorderSide(color: SkyColors.electric, width: 1.5)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: SkyColors.electricSoft, size: 22),
        ),
      ),
    );
  }

  Widget _board() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = min(
            constraints.maxWidth / _puzzle.cols,
            constraints.maxHeight / _puzzle.rows,
          );
          final boardW = cell * _puzzle.cols;
          final boardH = cell * _puzzle.rows;
          return Center(
            child: SizedBox(
              width: boardW,
              height: boardH,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Stack(
                    children: [
                      for (final c in _puzzle.cells)
                        Positioned(
                          left: c.col * cell,
                          top: c.row * cell,
                          width: cell,
                          height: cell,
                          child: _CellView(
                            cell: c,
                            size: cell,
                            powered: _powered.contains(
                                _puzzle.index(c.row, c.col)),
                            pulse: _pulseCtrl.value,
                            onTap: () => _onTapCell(c),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _bottomHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        _solved
            ? 'The altar is charged!'
            : 'Tap the clouds to route Zeus\u2019 lightning to the altar',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.85),
          shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
        ),
      ),
    );
  }

  Widget _winFlash() {
    return AnimatedBuilder(
      animation: _winCtrl,
      builder: (context, _) {
        if (_winCtrl.value == 0) return const SizedBox.shrink();
        final v = _winCtrl.value;
        final opacity = (sin(v * pi)) * 0.5;
        return IgnorePointer(
          child: Container(
            color: SkyColors.electricSoft.withValues(alpha: opacity),
          ),
        );
      },
    );
  }
}

class _CellView extends StatelessWidget {
  const _CellView({
    required this.cell,
    required this.size,
    required this.powered,
    required this.pulse,
    required this.onTap,
  });

  final Cell cell;
  final double size;
  final bool powered;
  final double pulse;
  final VoidCallback onTap;

  String get _hubAsset {
    switch (cell.hub) {
      case HubImage.tower:
        return 'assets/tower.webp';
      case HubImage.tree:
        return 'assets/tree.webp';
      case HubImage.cloud:
        return 'assets/cloud.webp';
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = size * 0.04;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: _content(),
      ),
    );
  }

  Widget _content() {
    if (cell.kind == CellKind.empty) {
      return Opacity(
        opacity: 0.5,
        child: Image.asset('assets/empry_tile.webp', fit: BoxFit.contain),
      );
    }

    final inner = size * 0.92;
    Widget base = Image.asset('assets/empry_tile.webp',
        fit: BoxFit.contain, opacity: const AlwaysStoppedAnimation(0.85));

    // Arms always drawn from the unrotated base mask; visual turns applied by
    // AnimatedRotation so logic and visuals stay in sync.
    Widget arms = CustomPaint(
      size: Size(inner, inner),
      painter: ArmsPainter(
        mask: cell.baseConnections,
        powered: powered,
        pulse: pulse,
      ),
    );

    Widget hub;
    switch (cell.kind) {
      case CellKind.source:
        hub = _glowImage('assets/zeus_hand.webp', 1.0, powered);
        break;
      case CellKind.target:
        hub = _glowImage('assets/stone_altar.webp', 0.74, powered);
        break;
      case CellKind.wire:
      default:
        hub = _glowImage(_hubAsset, 0.5, powered);
        break;
    }

    Widget rotating = AnimatedRotation(
      turns: cell.turns / 4,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: Stack(
        alignment: Alignment.center,
        children: [arms, hub],
      ),
    );

    // Source and target should not visually spin.
    if (cell.kind != CellKind.wire) {
      rotating = Stack(alignment: Alignment.center, children: [arms, hub]);
    }

    final lockBadge = (!cell.rotatable && cell.kind == CellKind.wire)
        ? Positioned(
            right: size * 0.06,
            top: size * 0.06,
            child: Icon(Icons.lock,
                size: size * 0.16,
                color: SkyColors.gold.withValues(alpha: 0.9)),
          )
        : null;

    return Stack(
      alignment: Alignment.center,
      children: [
        base,
        rotating,
        if (lockBadge != null) lockBadge,
      ],
    );
  }

  Widget _glowImage(String asset, double scale, bool powered) {
    return FractionallySizedBox(
      widthFactor: scale,
      heightFactor: scale,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: powered
              ? [
                  BoxShadow(
                    color: SkyColors.gold.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Image.asset(asset, fit: BoxFit.contain),
      ),
    );
  }
}

class _WinSheet extends StatelessWidget {
  const _WinSheet({
    required this.level,
    required this.moves,
    required this.stars,
    required this.hasNext,
    required this.onReplay,
    required this.onNext,
    required this.onMenu,
  });

  final int level;
  final int moves;
  final int stars;
  final bool hasNext;
  final VoidCallback onReplay;
  final VoidCallback? onNext;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF18254A), Color(0xFF0C1429)],
        ),
        border: Border.all(color: SkyColors.gold.withValues(alpha: 0.7), width: 2),
        boxShadow: [
          BoxShadow(
              color: SkyColors.gold.withValues(alpha: 0.25),
              blurRadius: 30,
              spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'LEVEL COMPLETE',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              color: SkyColors.goldBright,
            ),
          ),
          const SizedBox(height: 4),
          Text('Solved in $moves moves',
              style: const TextStyle(color: SkyColors.electricSoft)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 3; i++)
                Icon(
                  i <= stars ? Icons.star_rounded : Icons.star_border_rounded,
                  color: SkyColors.gold,
                  size: 46,
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SkyButton(
                    label: 'MENU', icon: Icons.home_rounded, onTap: onMenu),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SkyButton(
                    label: 'REPLAY', icon: Icons.refresh, onTap: onReplay),
              ),
            ],
          ),
          if (hasNext) ...[
            const SizedBox(height: 10),
            SkyButton(
              label: 'NEXT LEVEL',
              icon: Icons.arrow_forward_rounded,
              primary: true,
              width: double.infinity,
              onTap: onNext!,
            ),
          ],
        ],
      ),
    );
  }
}

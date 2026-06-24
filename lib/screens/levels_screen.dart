import 'package:flutter/material.dart';

import '../services/progress.dart';
import '../theme.dart';
import 'game_screen.dart';

class LevelsScreen extends StatefulWidget {
  const LevelsScreen({super.key, required this.progress});

  final Progress progress;

  @override
  State<LevelsScreen> createState() => _LevelsScreenState();
}

class _LevelsScreenState extends State<LevelsScreen> {
  Future<void> _openLevel(int level) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(level: level, progress: widget.progress),
      ),
    );
    if (result != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.webp', fit: BoxFit.cover),
          Container(color: SkyColors.deepNavy.withValues(alpha: 0.6)),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Material(
                        color: SkyColors.panel,
                        shape: const CircleBorder(
                            side: BorderSide(
                                color: SkyColors.electric, width: 1.5)),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => Navigator.pop(context),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(Icons.arrow_back,
                                color: SkyColors.electricSoft),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'SELECT LEVEL',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: SkyColors.goldBright,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                    ),
                    itemCount: kTotalLevels,
                    itemBuilder: (context, i) {
                      final level = i + 1;
                      final unlocked = widget.progress.isUnlocked(level);
                      final completed = widget.progress.isCompleted(level);
                      return _LevelTile(
                        level: level,
                        unlocked: unlocked,
                        completed: completed,
                        onTap: unlocked ? () => _openLevel(level) : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.unlocked,
    required this.completed,
    required this.onTap,
  });

  final int level;
  final bool unlocked;
  final bool completed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = completed
        ? SkyColors.gold
        : unlocked
            ? SkyColors.electric
            : SkyColors.dim;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: unlocked
                  ? [const Color(0xFF152544), const Color(0xFF0C1730)]
                  : [const Color(0xFF11192C), const Color(0xFF0B1120)],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
            boxShadow: unlocked
                ? [
                    BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 12)
                  ]
                : null,
          ),
          child: Center(
            child: unlocked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$level',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                                color: accent.withValues(alpha: 0.8),
                                blurRadius: 10)
                          ],
                        ),
                      ),
                      if (completed)
                        const Icon(Icons.star_rounded,
                            color: SkyColors.gold, size: 18),
                    ],
                  )
                : Icon(Icons.lock, color: SkyColors.dim, size: 26),
          ),
        ),
      ),
    );
  }
}

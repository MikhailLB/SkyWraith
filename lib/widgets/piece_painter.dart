import 'dart:math';
import 'package:flutter/material.dart';

import '../game/puzzle.dart';
import '../theme.dart';

/// Paints the glowing lightning "arms" of a conductor piece based on its
/// (unrotated) connection mask. Visual rotation is handled by the caller via
/// an [AnimatedRotation], so this always draws the base mask.
class ArmsPainter extends CustomPainter {
  ArmsPainter({required this.mask, required this.powered, required this.pulse});

  final int mask;
  final bool powered;
  final double pulse; // 0..1 animated glow factor

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final half = size.width / 2;
    final core = powered ? SkyColors.gold : SkyColors.electricSoft;
    final glow = powered ? SkyColors.goldBright : SkyColors.electric;
    final dimFactor = powered ? 1.0 : 0.6;

    final glowWidth = size.width * 0.20;
    final coreWidth = size.width * 0.085;

    for (final dir in kDirs) {
      if (mask & dir == 0) continue;
      final end = center +
          Offset(dCol(dir) * half, dRow(dir) * half);

      final glowPaint = Paint()
        ..color = glow.withValues(alpha: (0.18 + 0.18 * pulse) * dimFactor)
        ..strokeWidth = glowWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawLine(center, end, glowPaint);

      final corePaint = Paint()
        ..color = core.withValues(alpha: (0.85) * dimFactor)
        ..strokeWidth = coreWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(center, end, corePaint);
    }

    // Central node glow.
    final nodeRadius = size.width * (0.16 + 0.03 * pulse);
    canvas.drawCircle(
      center,
      nodeRadius,
      Paint()
        ..color = glow.withValues(alpha: (0.5 + 0.3 * pulse) * dimFactor)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      size.width * 0.07,
      Paint()..color = core.withValues(alpha: 0.95 * dimFactor),
    );
  }

  @override
  bool shouldRepaint(covariant ArmsPainter old) =>
      old.mask != mask || old.powered != powered || old.pulse != pulse;
}

/// Paints a short jagged lightning bolt from the source edge into the cell,
/// used as a decorative emitter accent.
class BoltSparkPainter extends CustomPainter {
  BoltSparkPainter({required this.seed, required this.pulse});
  final int seed;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed);
    final paint = Paint()
      ..color = SkyColors.electric.withValues(alpha: 0.6 * pulse)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 3; k++) {
      final path = Path();
      var p = Offset(size.width * 0.5, size.height * 0.5);
      path.moveTo(p.dx, p.dy);
      final ang = rng.nextDouble() * pi * 2;
      for (var i = 0; i < 4; i++) {
        p += Offset(cos(ang) * size.width * 0.12,
                sin(ang) * size.width * 0.12) +
            Offset((rng.nextDouble() - 0.5) * size.width * 0.18,
                (rng.nextDouble() - 0.5) * size.width * 0.18);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant BoltSparkPainter old) => old.pulse != pulse;
}

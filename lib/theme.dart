import 'package:flutter/material.dart';

class SkyColors {
  static const Color deepNavy = Color(0xFF0B1020);
  static const Color navy = Color(0xFF13203B);
  static const Color panel = Color(0xCC0E1730);
  static const Color gold = Color(0xFFFFC93C);
  static const Color goldBright = Color(0xFFFFE08A);
  static const Color electric = Color(0xFF45C7FF);
  static const Color electricSoft = Color(0xFFBDEBFF);
  static const Color dim = Color(0xFF4A5C82);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: SkyColors.deepNavy,
    colorScheme: base.colorScheme.copyWith(
      primary: SkyColors.gold,
      secondary: SkyColors.electric,
      surface: SkyColors.navy,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Roboto',
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
  );
}

/// A reusable Greek-styled action button.
class SkyButton extends StatelessWidget {
  const SkyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final accent = primary ? SkyColors.gold : SkyColors.electric;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: primary
                    ? [const Color(0xFF2A2140), const Color(0xFF1A1530)]
                    : [const Color(0xFF152544), const Color(0xFF0E1B33)],
              ),
              border: Border.all(color: accent.withValues(alpha: 0.7), width: 2),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: accent, size: 22),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Colors.white,
                      shadows: [
                        Shadow(color: accent.withValues(alpha: 0.8), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

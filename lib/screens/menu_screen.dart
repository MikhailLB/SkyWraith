import 'package:flutter/material.dart';

import '../services/progress.dart';
import '../theme.dart';
import 'game_screen.dart';
import 'levels_screen.dart';
import 'web_screen.dart';

const String kPrivacyUrl = 'https://skywratth.com/privacy-policy.html';
const String kSupportUrl = 'https://skywratth.com/support.html';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.progress});

  final Progress progress;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _play() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          level: widget.progress.unlockedLevel,
          progress: widget.progress,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _levels() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelsScreen(progress: widget.progress),
      ),
    );
    if (mounted) setState(() {});
  }

  void _openWeb(String title, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WebScreen(title: title, url: url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/bg.webp', fit: BoxFit.cover),
          Container(color: SkyColors.deepNavy.withValues(alpha: 0.5)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  Image.asset('assets/logo.webp', fit: BoxFit.contain),
                  const Spacer(flex: 2),
                  SkyButton(
                    label: widget.progress.unlockedLevel > 1
                        ? 'CONTINUE'
                        : 'PLAY',
                    icon: Icons.play_arrow_rounded,
                    primary: true,
                    width: double.infinity,
                    onTap: _play,
                  ),
                  const SizedBox(height: 14),
                  SkyButton(
                    label: 'LEVELS',
                    icon: Icons.grid_view_rounded,
                    width: double.infinity,
                    onTap: _levels,
                  ),
                  const Spacer(flex: 2),
                  Row(
                    children: [
                      Expanded(
                        child: _miniButton(
                          'Privacy Policy',
                          Icons.privacy_tip_outlined,
                          () => _openWeb('Privacy Policy', kPrivacyUrl),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _miniButton(
                          'Support',
                          Icons.support_agent_outlined,
                          () => _openWeb('Support', kSupportUrl),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniButton(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: SkyColors.panel,
            border: Border.all(
                color: SkyColors.electric.withValues(alpha: 0.4), width: 1.2),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: SkyColors.electricSoft),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      color: SkyColors.electricSoft,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/progress.dart';
import '../theme.dart';
import 'menu_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  late final Animation<double> _progress;
  late final AnimationController _dotsCtrl;
  bool _assetsPrecached = false;

  @override
  void initState() {
    super.initState();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // The bar advances smoothly to ~92% and only snaps to a full 100% in the
    // very last instant before the game launches.
    _progress = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.92).chain(
          CurveTween(curve: Curves.easeInOut),
        ),
        weight: 88,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.92, end: 1.0).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 12,
      ),
    ]).animate(_progressCtrl);

    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goToMenu();
    });

    _progressCtrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_assetsPrecached) {
      _assetsPrecached = true;
      for (final a in const [
        'assets/bg.webp',
        'assets/cloud.webp',
        'assets/empry_tile.webp',
        'assets/tower.webp',
        'assets/tree.webp',
        'assets/stone_altar.webp',
        'assets/zeus_hand.webp',
        'assets/logo.webp',
      ]) {
        precacheImage(AssetImage(a), context);
      }
    }
  }

  Future<void> _goToMenu() async {
    final progress = await Progress.load();
    // The game itself is strictly portrait.
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => MenuScreen(progress: progress),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SkyColors.deepNavy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final asset = isPortrait
              ? 'assets/Vertical_LoadingScreen.webp'
              : 'assets/Horizontal_LoadingScreen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.15)),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isPortrait ? 36 : 90,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _loadingLabel(),
                      const SizedBox(height: 14),
                      _progressBar(),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _loadingLabel() {
    return AnimatedBuilder(
      animation: _dotsCtrl,
      builder: (context, _) {
        final count = (_dotsCtrl.value * 4).floor() % 4;
        final dots = '.' * count;
        return Text(
          'Loading$dots',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 3,
            color: SkyColors.goldBright,
            shadows: [
              const Shadow(color: Colors.black, blurRadius: 8),
              Shadow(
                  color: SkyColors.gold.withValues(alpha: 0.6), blurRadius: 16),
            ],
          ),
        );
      },
    );
  }

  Widget _progressBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return AnimatedBuilder(
          animation: _progress,
          builder: (context, _) {
            return Container(
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black.withValues(alpha: 0.45),
                border: Border.all(
                    color: SkyColors.electric.withValues(alpha: 0.7),
                    width: 1.5),
              ),
              padding: const EdgeInsets.all(3),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  // Fills strictly left -> right.
                  widthFactor: _progress.value.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      gradient: const LinearGradient(
                        colors: [SkyColors.electric, SkyColors.goldBright],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: SkyColors.electric.withValues(alpha: 0.7),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    width: w,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../theme.dart';

// ============================================================
// OFFLINE STAGE — "No connection" screen with retry
// ============================================================
// Layout uses the pre-rendered gray asset as full-bleed
// background and overlays a single Retry pill at the safe-area
// bottom. The pill leans on the same lightning palette as the
// rest of the gray flow so it reads as part of the same world.
//
// Re-entry mechanism: the parent provides `rebuilder` — a
// builder that knows how to recreate whatever stage routed us
// here (BootStage on cold path, PortalStage on warm path).
// ============================================================

class OfflineStage extends StatefulWidget {
  const OfflineStage({
    super.key,
    required this.rebuilder,
  });

  final WidgetBuilder rebuilder;

  @override
  State<OfflineStage> createState() => _OfflineStageState();
}

class _OfflineStageState extends State<OfflineStage>
    with TickerProviderStateMixin {
  bool _retrying = false;
  late final AnimationController _haloCtrl;
  late final Animation<double> _haloAnim;

  @override
  void initState() {
    super.initState();
    _haloCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _haloAnim = Tween<double>(begin: 0.35, end: 0.95).animate(
      CurvedAnimation(parent: _haloCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _haloCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRetry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: widget.rebuilder),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SkyColors.deepNavy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final size = MediaQuery.of(context).size;
          final asset = isPortrait
              ? 'assets/gray/offline_portrait.webp'
              : 'assets/gray/offline_landscape.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.12)),
              Positioned(
                left: isPortrait ? size.width * 0.12 : size.width * 0.32,
                right: isPortrait ? size.width * 0.12 : size.width * 0.32,
                bottom: isPortrait
                    ? size.height * 0.085
                    : size.height * 0.10,
                child: AnimatedBuilder(
                  animation: _haloAnim,
                  builder: (_, _) => _PillRetry(
                    glow: _haloAnim.value,
                    retrying: _retrying,
                    onPressed: _onRetry,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PillRetry extends StatelessWidget {
  const _PillRetry({
    required this.glow,
    required this.retrying,
    required this.onPressed,
  });

  final double glow;
  final bool retrying;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: retrying ? null : onPressed,
        borderRadius: BorderRadius.circular(36),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: retrying
                ? null
                : const LinearGradient(
                    colors: [SkyColors.electric, SkyColors.goldBright],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: retrying ? Colors.black.withValues(alpha: 0.55) : null,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: SkyColors.electric.withValues(alpha: 0.8),
              width: 1.6,
            ),
            boxShadow: retrying
                ? null
                : [
                    BoxShadow(
                      color: SkyColors.electric.withValues(alpha: glow * 0.7),
                      blurRadius: 16 + glow * 14,
                      spreadRadius: glow * 2,
                    ),
                  ],
          ),
          alignment: Alignment.center,
          child: retrying
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(SkyColors.electric),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Reaching out…',
                      style: TextStyle(
                        color: SkyColors.electricSoft,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        fontSize: 15,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.refresh_rounded,
                        size: 22, color: SkyColors.deepNavy),
                    SizedBox(width: 8),
                    Text(
                      'RETRY',
                      style: TextStyle(
                        color: SkyColors.deepNavy,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

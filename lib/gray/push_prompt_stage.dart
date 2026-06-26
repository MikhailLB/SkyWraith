import 'package:flutter/material.dart';

import '../core/network_probe.dart';
import '../core/persistence_store.dart';
import '../core/push_relay.dart';
import '../setup/sky_config.dart';
import '../theme.dart';
import 'portal_stage.dart' deferred as portal;

// ============================================================
// PUSH PROMPT STAGE — One-time push opt-in promo
// ============================================================
// Layout — full bleed gray asset (Vertical/Horizontal
// notif*.webp) with two stacked actions near the bottom edge:
//   - Accept primary (electric chevron with arc glow)
//   - Skip secondary (ghost outline)
//
// On Accept we always head to the portal regardless of the
// system response — the only difference is whether the OS
// dialog opened, and PersistenceStore handles the OS-denied
// edge case so we never re-show this screen for the same user.
// On Skip we set the 72h cooldown and pass through.
// ============================================================

class PushPromptStage extends StatefulWidget {
  const PushPromptStage({
    super.key,
    required this.store,
    required this.relay,
    required this.probe,
    required this.portalUrl,
  });

  final PersistenceStore store;
  final PushRelay relay;
  final NetworkProbe probe;
  final String portalUrl;

  @override
  State<PushPromptStage> createState() => _PushPromptStageState();
}

class _PushPromptStageState extends State<PushPromptStage> {
  bool _busy = false;

  Future<void> _onAccept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final granted = await widget.relay.requestSystemPermission();
    if (!granted) {
      final cooldown = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
          SkyConfig.promptCooldownSeconds;
      await widget.store.markPromoCooldown(cooldown);
    }
    if (!mounted) return;
    await _forwardToPortal();
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    final cooldown = DateTime.now().millisecondsSinceEpoch ~/ 1000 +
        SkyConfig.promptCooldownSeconds;
    await widget.store.markPromoCooldown(cooldown);
    if (!mounted) return;
    await _forwardToPortal();
  }

  Future<void> _forwardToPortal() async {
    await portal.loadLibrary();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => portal.PortalStage(
          url: widget.portalUrl,
          store: widget.store,
          relay: widget.relay,
          probe: widget.probe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SkyColors.deepNavy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final size = MediaQuery.of(context).size;
          final isPortrait = orientation == Orientation.portrait;
          final asset = isPortrait
              ? 'assets/gray/notif_portrait.webp'
              : 'assets/gray/notif_landscape.webp';

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(asset, fit: BoxFit.cover),
              if (isPortrait)
                Positioned(
                  left: size.width * 0.10,
                  right: size.width * 0.10,
                  bottom: size.height * 0.075,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ChevronAcceptButton(
                        label: 'Accept',
                        onTap: _busy ? null : _onAccept,
                      ),
                      const SizedBox(height: 14),
                      _GhostSkipButton(
                        label: 'Skip',
                        onTap: _busy ? null : _onSkip,
                      ),
                    ],
                  ),
                )
              else
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: size.height * 0.07,
                  child: Center(
                    child: SizedBox(
                      width: size.width * 0.40,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ChevronAcceptButton(
                            label: 'Accept',
                            onTap: _busy ? null : _onAccept,
                            compact: true,
                          ),
                          const SizedBox(height: 10),
                          _GhostSkipButton(
                            label: 'Skip',
                            onTap: _busy ? null : _onSkip,
                            compact: true,
                          ),
                        ],
                      ),
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

/// Electric chevron-shaped primary action. The asymmetric notch
/// keeps this design visually distinct from any other gray-flow
/// button on the portfolio.
class _ChevronAcceptButton extends StatefulWidget {
  const _ChevronAcceptButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_ChevronAcceptButton> createState() => _ChevronAcceptButtonState();
}

class _ChevronAcceptButtonState extends State<_ChevronAcceptButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late final Animation<double> _glowAnim;
  bool _down = false;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.30, end: 0.85)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_glow);
  }

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.compact
        ? const EdgeInsets.symmetric(vertical: 12, horizontal: 18)
        : const EdgeInsets.symmetric(vertical: 18, horizontal: 26);
    final fontSize = widget.compact ? 16.0 : 19.0;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 90),
        child: AnimatedBuilder(
          animation: _glowAnim,
          builder: (_, _) => CustomPaint(
            painter: _ChevronPainter(
              glow: _glowAnim.value,
              pressed: _down,
            ),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded,
                      size: fontSize + 4, color: SkyColors.deepNavy),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: SkyColors.deepNavy,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter({required this.glow, required this.pressed});

  final double glow;
  final bool pressed;

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 14.0;
    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(0, size.height)
      ..close();

    final glowPaint = Paint()
      ..color = SkyColors.electric.withValues(alpha: pressed ? 0.25 : glow)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        pressed ? 4 : 10 + glow * 10,
      );
    canvas.drawPath(path, glowPaint);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: pressed
            ? const [SkyColors.electricSoft, SkyColors.electric]
            : const [SkyColors.goldBright, SkyColors.electric],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = SkyColors.deepNavy.withValues(alpha: 0.7);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) =>
      old.glow != glow || old.pressed != pressed;
}

class _GhostSkipButton extends StatefulWidget {
  const _GhostSkipButton({
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool compact;

  @override
  State<_GhostSkipButton> createState() => _GhostSkipButtonState();
}

class _GhostSkipButtonState extends State<_GhostSkipButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final padding = widget.compact
        ? const EdgeInsets.symmetric(vertical: 8, horizontal: 26)
        : const EdgeInsets.symmetric(vertical: 12, horizontal: 32);
    final fontSize = widget.compact ? 14.0 : 16.0;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) {
              setState(() => _down = false);
              widget.onTap!();
            },
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedOpacity(
        opacity: _down ? 0.55 : 0.92,
        duration: const Duration(milliseconds: 90),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            border: Border.all(
              color: SkyColors.electric.withValues(alpha: 0.7),
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(40),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: SkyColors.electricSoft,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
            ),
          ),
        ),
      ),
    );
  }
}

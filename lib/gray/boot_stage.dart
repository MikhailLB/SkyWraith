import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/attribution_tracker.dart';
import '../core/config_gateway.dart';
import '../core/network_probe.dart';
import '../core/persistence_store.dart';
import '../core/push_relay.dart';
import '../screens/loading_screen.dart';
import '../setup/sky_config.dart';
import '../state/launch_mode.dart';
import '../theme.dart';
import 'offline_stage.dart';
import 'portal_stage.dart' deferred as portal;
import 'push_prompt_stage.dart';

// ============================================================
// BOOT STAGE — Routing orchestrator + loading UI
// ============================================================
// Owns the very first second of the app: it spins the gray
// flow when needed, then hands control off to either the
// WebView portal or the existing arcade puzzle game. The
// `portal_stage.dart` import is deferred so the WebView engine
// (~3 MB) is NOT linked into the arcade-only code path.
//
// Loading bar contract:
//   - Bar advances in measured steps as each milestone of the
//     flow completes (push init → connectivity → attribution →
//     config response).
//   - It NEVER reaches 100% until `_finalize()` is called right
//     before the navigation away. That guarantees the user sees
//     a fully-loaded bar exactly when the screen flips, instead
//     of a confusing "100% then we keep waiting" state.
//   - "Loading" text shows one to three dots, cycling every
//     400 ms via a separate controller.
// ============================================================

// Discrete milestones the bar advances through. Each value is
// the bar fill ratio at the END of that milestone.
const double _kStepPushReady = 0.18;
const double _kStepConnectivity = 0.42;
const double _kStepAttribution = 0.68;
const double _kStepGatewayDone = 0.88;
const double _kStepFinal = 1.0;

class BootStage extends StatefulWidget {
  const BootStage({
    super.key,
    required this.store,
    required this.probe,
    required this.tracker,
    required this.gateway,
    required this.relay,
  });

  final PersistenceStore store;
  final NetworkProbe probe;
  final AttributionTracker tracker;
  final ConfigGateway gateway;
  final PushRelay relay;

  @override
  State<BootStage> createState() => _BootStageState();
}

class _BootStageState extends State<BootStage>
    with TickerProviderStateMixin {
  late final AnimationController _dotsCtrl;
  bool _navigated = false;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _orchestrate();
  }

  @override
  void dispose() {
    _dotsCtrl.dispose();
    super.dispose();
  }

  void _bumpProgress(double target) {
    if (!mounted) return;
    if (target <= _progress) return;
    setState(() => _progress = target);
  }

  Future<void> _finalize() async {
    _bumpProgress(_kStepFinal);
    // Give the bar ~280 ms to visually reach the right edge
    // before the route swap. Anything shorter looks like the
    // bar jumps to 100% AFTER the new screen is already drawing.
    await Future<void>.delayed(const Duration(milliseconds: 280));
  }

  Future<void> _orchestrate() async {
    widget.relay.onTokenRotate = _refireConfigOnTokenRotate;
    await widget.relay.awaken().catchError((_) {});
    _bumpProgress(_kStepPushReady);

    // Every launch — first or hundredth — hits the config
    // endpoint. The previously stored LaunchMode is treated as
    // a hint, not a routing shortcut, so a backend that flips a
    // user from arcade to portal (or vice versa) takes effect
    // on the very next cold start.
    await _executeFreshDecisionFlow();
  }

  Future<void> _refireConfigOnTokenRotate(String token) async {
    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleBody(
      locale: locale,
      pushToken: token,
    );
    await widget.gateway.request(body);
  }

  // ------------- single decision flow -------------

  /// Runs the full attribution → config roundtrip on EVERY
  /// launch. No URL ever lives across launches; the destination
  /// the user sees is whatever the backend hands us right now.
  Future<void> _executeFreshDecisionFlow() async {
    final priorMode = widget.store.readLaunchMode();

    if (!await widget.probe.hasReachableUplink()) {
      // No connection — defer to historic mode so arcade users
      // can keep playing offline. Portal-tagged users see the
      // offline screen so they can retry once back online.
      if (priorMode == LaunchMode.arcade) {
        await _flipToArcade();
      } else {
        _flipToOffline();
      }
      return;
    }
    _bumpProgress(_kStepConnectivity);

    // Push URL skips attribution — it's a deliberate live link
    // delivered to this user by the push system.
    final pushUrl = await widget.store.drainPushUrl();
    if (pushUrl != null) {
      _bumpProgress(_kStepAttribution);
      _bumpProgress(_kStepGatewayDone);
      await widget.store.writeLaunchMode(LaunchMode.portal);
      await _flipToPortal(pushUrl);
      return;
    }

    await widget.tracker.ignite();

    // Genuinely first-time users get the full 30 s attribution
    // budget; returning users cap at 10 s so boot stays snappy
    // even when the SDK is slow to call back.
    final attributionFuture = priorMode == LaunchMode.unresolved
        ? widget.tracker.awaitInstall()
        : widget.tracker.awaitInstall().timeout(
              Duration(seconds: SkyConfig.returningAttributionTimeoutSeconds),
              onTimeout: () => <String, dynamic>{},
            );
    await Future.wait([attributionFuture, widget.tracker.awaitDeepLink()]);
    _bumpProgress(_kStepAttribution);

    final locale = Platform.localeName.replaceAll('-', '_');
    final body = await widget.tracker.assembleBody(
      locale: locale,
      pushToken: widget.relay.token,
    );
    final reply = await widget.gateway.request(body);
    _bumpProgress(_kStepGatewayDone);

    if (reply.transportOk) {
      // Backend spoke — trust the fresh verdict and update the
      // LaunchMode hint for future offline launches.
      if (reply.ok && reply.hasUrl) {
        await widget.store.writeLaunchMode(LaunchMode.portal);
        await _flipToPortal(reply.url!);
      } else {
        await widget.store.writeLaunchMode(LaunchMode.arcade);
        await _flipToArcade();
      }
      return;
    }

    // Backend unreachable. Fall back to the last known mode;
    // unresolved → offline screen, arcade → game, portal → offline.
    switch (priorMode) {
      case LaunchMode.arcade:
        await _flipToArcade();
        break;
      case LaunchMode.portal:
      case LaunchMode.unresolved:
        _flipToOffline();
        break;
    }
  }

  // ------------- navigation helpers -------------

  Future<void> _flipToPortal(String url) async {
    if (_navigated || !mounted) return;
    _navigated = true;

    await portal.loadLibrary();
    await _finalize();
    if (!mounted) return;

    if (widget.store.shouldShowPromo()) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PushPromptStage(
            store: widget.store,
            relay: widget.relay,
            probe: widget.probe,
            portalUrl: url,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => portal.PortalStage(
            url: url,
            store: widget.store,
            relay: widget.relay,
            probe: widget.probe,
          ),
        ),
      );
    }
  }

  Future<void> _flipToArcade() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    await _finalize();
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, __, ___) => const LoadingScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _flipToOffline() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          rebuilder: (_) => BootStage(
            store: widget.store,
            probe: widget.probe,
            tracker: widget.tracker,
            gateway: widget.gateway,
            relay: widget.relay,
          ),
        ),
      ),
    );
  }

  // ------------- UI -------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SkyColors.deepNavy,
      body: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final bg = isPortrait
              ? 'assets/Vertical_LoadingScreen.webp'
              : 'assets/Horizontal_LoadingScreen.webp';
          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(bg, fit: BoxFit.cover),
              Container(color: Colors.black.withValues(alpha: 0.20)),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isPortrait ? 36 : 110,
                    0,
                    isPortrait ? 36 : 110,
                    isPortrait ? 36 : 28,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _LoadingLabel(controller: _dotsCtrl),
                      const SizedBox(height: 14),
                      _ProgressTrack(progress: _progress),
                      const SizedBox(height: 18),
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
}

/// "Loading" with up to three trailing dots that cycle every
/// ~350 ms (the controller repeats over 1.4 s, so we sample
/// `value * 4 floor mod 4` for one-of-four dot counts).
class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final count = (controller.value * 4).floor() % 4;
        return Text(
          'Loading${'.' * count}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
            color: SkyColors.goldBright,
            shadows: [
              Shadow(blurRadius: 8, color: Colors.black87),
              Shadow(blurRadius: 16, color: Color(0x66FFC93C)),
            ],
          ),
        );
      },
    );
  }
}

/// Horizontal progress bar that smoothly interpolates between
/// the previous and new fill ratio whenever the parent calls
/// `setState(() => _progress = ...)`.
class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Container(
          height: 18,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.black.withValues(alpha: 0.55),
            border: Border.all(
              color: SkyColors.electric.withValues(alpha: 0.75),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0.0, end: progress.clamp(0.0, 1.0)),
                builder: (_, value, _) {
                  return SizedBox(
                    width: width * value,
                    height: double.infinity,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [SkyColors.electric, SkyColors.goldBright],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0xB345C7FF),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/branded_http.dart';
import '../core/network_probe.dart';
import '../core/persistence_store.dart';
import '../core/push_relay.dart';
import '../setup/sky_config.dart';
import '../theme.dart';
import 'offline_stage.dart';

// ============================================================
// PORTAL STAGE — Full-screen WebView shell (gray UI)
// ============================================================
// Responsibilities:
//   - host the partner URL inside an immersive WebView,
//   - keep the keyboard from hiding inputs on Android (the
//     three-layer fix: manifest adjustResize +
//     resizeToAvoidBottomInset:false + JS scrollIntoView),
//   - kill safe-area insets injected by sites built for iOS,
//   - cover the native ERR_NAME_NOT_RESOLVED screen with our
//     own spinner when connectivity drops,
//   - debounce VPN-flicker `[ConnectivityResult.none]` frames
//     before flipping to OfflineStage (700 ms blind spot),
//   - recover from short affiliate redirect storms (3 tries
//     against the last known good URL),
//   - keep the back button inside the WebView history — the
//     app must never exit on back press.
// ============================================================

/// Pre-warm hook called from BootStage right after the deferred
/// library loads. Currently a no-op — kept for future
/// integrations (e.g. wiring up a service worker shim).
Future<void> warmEngine() async {}

class PortalStage extends StatefulWidget {
  const PortalStage({
    super.key,
    required this.url,
    required this.store,
    required this.relay,
    required this.probe,
  });

  final String url;
  final PersistenceStore store;
  final PushRelay relay;
  final NetworkProbe probe;

  @override
  State<PortalStage> createState() => _PortalStageState();
}

class _PortalStageState extends State<PortalStage>
    with WidgetsBindingObserver {
  late final WebViewController _controller;

  bool _spinning = true;
  bool _offlineRouted = false;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _offlineDebounce;

  String? _lastMainFrameUrl;
  int _redirectRetries = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _enterImmersiveMode();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(brandedHttp.currentUserAgent)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(_buildDelegate())
      ..enableZoom(false);

    _configureAndroid();
    _controller.loadRequest(Uri.parse(widget.url));

    widget.relay.onLiveUrl = (url) {
      if (mounted) _controller.loadRequest(Uri.parse(url));
    };

    _connSub = widget.probe.pulse.listen(_onConnectivityFrame);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _enterImmersiveMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connSub?.cancel();
    _offlineDebounce?.cancel();
    widget.relay.onLiveUrl = null;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _enterImmersiveMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  // ---- navigation delegate ----

  NavigationDelegate _buildDelegate() => NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _spinning = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _spinning = false);
          _redirectRetries = 0;
          _stripSafeAreas();
          _wireKeyboardScrollFix();
        },
        onWebResourceError: (err) {
          if (err.isForMainFrame != true) return;
          final blurb = err.description.toLowerCase();

          // Short affiliate redirect storms first.
          final isLoop = blurb.contains('too_many_redirects') ||
              blurb.contains('too many redirects') ||
              err.errorCode == -1007 ||
              err.errorCode == -9;
          if (isLoop &&
              _lastMainFrameUrl != null &&
              _redirectRetries < 3) {
            _redirectRetries++;
            _controller.loadRequest(Uri.parse(_lastMainFrameUrl!));
            return;
          }

          // Cover the native error page immediately.
          if (mounted) setState(() => _spinning = true);

          final isDnsOrDisconnect =
              blurb.contains('name_not_resolved') ||
                  blurb.contains('err_name_not_resolved') ||
                  blurb.contains('internet_disconnected') ||
                  blurb.contains('network_changed') ||
                  err.errorCode == -2 ||
                  err.errorCode == -105 ||
                  err.errorCode == -106 ||
                  err.errorCode == -21;
          if (isDnsOrDisconnect) {
            _routeToOfflineDirect();
          } else {
            _routeToOfflineIfDown();
          }
        },
        onHttpError: (_) {},
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null) return NavigationDecision.prevent;
          final scheme = uri.scheme;
          if (scheme == 'http' ||
              scheme == 'https' ||
              scheme == 'about' ||
              scheme == 'data' ||
              scheme == 'blob') {
            if (request.isMainFrame) _lastMainFrameUrl = request.url;
            return NavigationDecision.navigate;
          }
          _launchExternal(uri);
          return NavigationDecision.prevent;
        },
      );

  void _configureAndroid() {
    if (!Platform.isAndroid) return;
    final platform = _controller.platform;
    if (platform is! AndroidWebViewController) return;

    platform.setMediaPlaybackRequiresUserGesture(false);

    // `<input type="file">` support. Without this the picker
    // never opens on Android (Chrome WebView default).
    platform.setOnShowFileSelector(_pickFilesForWebView);

    // Third-party cookies — most affiliate/casino sites need them.
    final cookieManager = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams
          .fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
    );
    cookieManager.setAcceptThirdPartyCookies(platform, true);
  }

  Future<List<String>> _pickFilesForWebView(FileSelectorParams params) async {
    try {
      final accept = params.acceptTypes
          .map((t) => t.toLowerCase().trim())
          .where((t) => t.isNotEmpty)
          .toList();

      // Map common accept tokens to FilePicker types. Anything
      // ambiguous (e.g. "*/*" or a mixed list) falls through to
      // FileType.any so we never silently drop a selection.
      FileType type = FileType.any;
      List<String>? customExts;
      if (accept.length == 1) {
        final value = accept.single;
        if (value.startsWith('image/')) {
          type = FileType.image;
        } else if (value.startsWith('video/')) {
          type = FileType.video;
        } else if (value.startsWith('audio/')) {
          type = FileType.audio;
        } else if (value.startsWith('.') && value.length > 1) {
          type = FileType.custom;
          customExts = [value.substring(1)];
        }
      } else if (accept.isNotEmpty &&
          accept.every((v) => v.startsWith('.') && v.length > 1)) {
        type = FileType.custom;
        customExts = accept.map((v) => v.substring(1)).toList();
      }

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: params.mode == FileSelectorMode.openMultiple,
        type: type,
        allowedExtensions: customExts,
        withData: false,
      );
      if (result == null) return const [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => Uri.file(f.path!).toString())
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---- connectivity ----

  void _onConnectivityFrame(List<ConnectivityResult> results) {
    final allNone = results.every((r) => r == ConnectivityResult.none);
    if (!allNone) {
      _offlineDebounce?.cancel();
      return;
    }
    _offlineDebounce?.cancel();
    _offlineDebounce = Timer(
      Duration(milliseconds: SkyConfig.connectivityDebounceMs),
      _routeToOfflineDirect,
    );
  }

  Future<void> _routeToOfflineIfDown() async {
    if (_offlineRouted) return;
    if (await widget.probe.hasReachableUplink()) return;
    _routeToOfflineDirect();
  }

  void _routeToOfflineDirect() {
    if (_offlineRouted || !mounted) return;
    _offlineRouted = true;
    _safeNavigateToOffline();
  }

  Future<void> _safeNavigateToOffline() async {
    final currentUrl = await _controller.currentUrl() ?? widget.url;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OfflineStage(
          rebuilder: (_) => PortalStage(
            url: currentUrl,
            store: widget.store,
            relay: widget.relay,
            probe: widget.probe,
          ),
        ),
      ),
    );
  }

  Future<void> _launchExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ---- JS injections ----

  void _wireKeyboardScrollFix() {
    _controller.runJavaScript(r"""
(function() {
  if (window.__skyKbReady) return;
  window.__skyKbReady = true;

  function editable(el) {
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable);
  }

  function nudge() {
    var el = document.activeElement;
    if (!editable(el)) return;
    var vp = window.visualViewport;
    if (vp) {
      var rect = el.getBoundingClientRect();
      var floor = vp.offsetTop + vp.height;
      if (rect.bottom > floor - 24 || rect.top < vp.offsetTop) {
        el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
      }
    } else {
      el.scrollIntoView({ behavior: 'auto', block: 'nearest' });
    }
  }

  document.addEventListener('focusin', function(e) {
    if (editable(e.target)) setTimeout(nudge, 320);
  });

  if (window.visualViewport) {
    var lastH = window.visualViewport.height;
    window.visualViewport.addEventListener('resize', function() {
      var h = window.visualViewport.height;
      if (h < lastH) setTimeout(nudge, 110);
      lastH = h;
    });
  }
})();
""");
  }

  void _stripSafeAreas() {
    _controller.runJavaScript(r"""
(function() {
  if (window.__skySafeArea) return;
  window.__skySafeArea = true;

  var TAG = '__sky_zeroSafe';
  var CSS =
    ':root{' +
      '--safe-area-inset-top:0px!important;' +
      '--safe-area-inset-right:0px!important;' +
      '--safe-area-inset-bottom:0px!important;' +
      '--safe-area-inset-left:0px!important;' +
      '--sat:0px!important;--sar:0px!important;' +
      '--sab:0px!important;--sal:0px!important;' +
    '}' +
    'html,body,#__nuxt,#__layout,#app,#root{' +
      'padding-top:0!important;' +
      'padding-left:0!important;' +
      'padding-right:0!important;' +
      'margin-top:0!important;' +
    '}';

  function kbVisible() {
    var v = window.visualViewport;
    if (!v) return false;
    return v.height < window.innerHeight * 0.78;
  }

  function apply() {
    if (kbVisible()) return;
    var head = document.head || document.documentElement;
    if (!head) return;
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta && !/viewport-fit\s*=\s*contain/i.test(meta.getAttribute('content') || '')) {
      var c = (meta.getAttribute('content') || '')
        .replace(/,?\s*viewport-fit\s*=\s*\w+/ig, '').trim();
      meta.setAttribute('content', c + (c ? ', ' : '') + 'viewport-fit=contain');
    }
    var node = document.getElementById(TAG);
    if (!node) {
      node = document.createElement('style');
      node.id = TAG;
      head.appendChild(node);
    }
    if (node.textContent !== CSS) node.textContent = CSS;
    if (head.lastElementChild !== node) head.appendChild(node);
  }

  apply();
  ['pushState','replaceState'].forEach(function(name) {
    var orig = history[name];
    history[name] = function() {
      var out = orig.apply(this, arguments);
      setTimeout(apply, 80);
      setTimeout(apply, 380);
      return out;
    };
  });
  window.addEventListener('popstate', function() { setTimeout(apply, 80); });
  setInterval(apply, 2600);
})();
""");
  }

  // ---- back button ----

  Future<bool> _onBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
    }
    return false;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    // Respect display cutouts / notches on every side that has
    // physical hardware in the way. Status / nav bars are
    // hidden by `immersiveSticky`, so their viewPadding is 0 in
    // steady state — what stays non-zero are the camera punch
    // hole (which migrates to a side in landscape) and the
    // gesture handle area on some OEM skins.
    final viewPadding = MediaQuery.of(context).viewPadding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _onBack();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false, // critical for keyboard fix.
        body: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: viewPadding.top,
                left: viewPadding.left,
                right: viewPadding.right,
                bottom: viewPadding.bottom,
              ),
              child: WebViewWidget(controller: _controller),
            ),
            if (_spinning)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                child: const Center(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(SkyColors.electric),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

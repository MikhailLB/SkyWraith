import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:flutter/foundation.dart';

import '../setup/sky_config.dart';
import '../setup/tracker_secrets.dart';
import 'branded_http.dart';

// ============================================================
// ATTRIBUTION TRACKER — AppsFlyer wrapper + GCD retry
// ============================================================
// Three sources of attribution land on three different SDK
// callbacks, in an order we cannot control:
//
//   onInstallConversionData  — primary, populated within ~1s
//                              on first launch, never afterwards
//   onAppOpenAttribution     — fired on every cold start
//   onDeepLinking            — deep link parser (OneLink / UDL)
//
// We collect all three, merge them in attribution-first order,
// and sprinkle device metadata on top. Backend wants the raw
// AppsFlyer field names — we touch *nothing* from the payload.
//
// Organic false-positive rescue:
// AppsFlyer occasionally reports `af_status: Organic` for a
// definitively paid install (timing bug on first-run). The
// rescue plan is:
//   1. delay `organicRetryDelaySeconds` (5s) for the SDK to
//      catch up,
//   2. hit the GCD API directly with the AppsFlyer UID,
//   3. trust the latter payload if it deviates from Organic.
// ============================================================

class AttributionTracker {
  AppsflyerSdk? _sdk;
  bool _initStarted = false;

  Map<String, dynamic>? _installPayload;
  Map<String, dynamic>? _openPayload;
  Map<String, dynamic>? _deepLinkPayload;

  final Completer<Map<String, dynamic>> _installArrived =
      Completer<Map<String, dynamic>>();
  final Completer<void> _deepLinkArrived = Completer<void>();

  Future<void> ignite() async {
    if (_initStarted) return;
    _initStarted = true;

    if (SkyConfig.trackerKey.isEmpty) {
      // No SDK key yet — let the callers proceed without
      // attribution. SplashScreen still finishes routing,
      // just without paid signal in the body.
      if (!_installArrived.isCompleted) {
        _installArrived.complete(<String, dynamic>{});
      }
      if (!_deepLinkArrived.isCompleted) _deepLinkArrived.complete();
      return;
    }

    final options = AppsFlyerOptions(
      afDevKey: SkyConfig.trackerKey,
      appId: SkyConfig.storeAnalyticsId,
      showDebug: kDebugMode,
      timeToWaitForATTUserAuthorization: 10,
    );

    _sdk = AppsflyerSdk(options);

    _sdk!.onInstallConversionData((data) async {
      final payload = _extractPayload(data);
      if (_isOrganic(payload)) {
        await Future<void>.delayed(
          Duration(seconds: SkyConfig.organicRetryDelaySeconds),
        );
        final rescue = await _runGcdRescue();
        _installPayload = rescue ?? payload;
      } else {
        _installPayload = payload;
      }
      if (!_installArrived.isCompleted) {
        _installArrived.complete(_installPayload ?? <String, dynamic>{});
      }
    });

    _sdk!.onAppOpenAttribution((data) {
      _openPayload = _extractPayload(data);
    });

    _sdk!.onDeepLinking((result) {
      try {
        final clickEvent = result.deepLink?.clickEvent;
        if (clickEvent != null) {
          _deepLinkPayload = Map<String, dynamic>.from(clickEvent);
        }
      } catch (_) {}
      if (!_deepLinkArrived.isCompleted) _deepLinkArrived.complete();
    });

    try {
      await _sdk!.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[AttributionTracker] initSdk failed: $e');
      if (!_installArrived.isCompleted) {
        _installArrived.complete(<String, dynamic>{});
      }
      if (!_deepLinkArrived.isCompleted) _deepLinkArrived.complete();
    }
  }

  Future<Map<String, dynamic>> awaitInstall() {
    return _installArrived.future.timeout(
      Duration(seconds: SkyConfig.attributionWaitSeconds),
      onTimeout: () => <String, dynamic>{},
    );
  }

  Future<void> awaitDeepLink() {
    return _deepLinkArrived.future.timeout(
      Duration(seconds: SkyConfig.deepLinkWaitSeconds),
      onTimeout: () {},
    );
  }

  Future<String?> trackerUid() async {
    if (_sdk == null) return null;
    try {
      return await _sdk!.getAppsFlyerUID();
    } catch (_) {
      return null;
    }
  }

  /// Build the POST body for the config endpoint.
  ///
  /// Order is meaningful: install payload wins for every key,
  /// then deep link / open attribution fill missing gaps, then
  /// device-side fields overwrite duplicates.
  Future<Map<String, dynamic>> assembleBody({
    required String locale,
    String? pushToken,
  }) async {
    final body = <String, dynamic>{};

    if (_installPayload != null) body.addAll(_installPayload!);
    _deepLinkPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));
    _openPayload?.forEach((k, v) => body.putIfAbsent(k, () => v));

    body['af_id'] = await trackerUid() ?? '';
    body['bundle_id'] = SkyConfig.packageName;
    body['os'] = Platform.isAndroid ? 'Android' : 'iOS';
    body['store_id'] = SkyConfig.storeListingId;
    body['locale'] = locale;

    if (pushToken != null && pushToken.isNotEmpty) {
      body['push_token'] = pushToken;
    }
    if (SkyConfig.messagingProjectId.isNotEmpty) {
      body['firebase_project_id'] = SkyConfig.messagingProjectId;
    }

    if (kDebugMode) {
      debugPrint('[AttributionTracker] body=${jsonEncode(body)}');
    }
    return body;
  }

  // ------------- internals -------------

  Map<String, dynamic> _extractPayload(dynamic raw) {
    if (raw is Map) {
      final inner = raw['payload'];
      if (inner is Map) {
        return Map<String, dynamic>.from(inner);
      }
      return Map<String, dynamic>.from(raw);
    }
    return <String, dynamic>{};
  }

  bool _isOrganic(Map<String, dynamic> payload) {
    final status = payload['af_status'];
    return status is String && status.toLowerCase() == 'organic';
  }

  Future<Map<String, dynamic>?> _runGcdRescue() async {
    final uid = await trackerUid();
    if (uid == null || uid.isEmpty) return null;
    final appId = Platform.isIOS
        ? SkyConfig.storeAnalyticsId
        : SkyConfig.packageName;
    final probeUrl = buildGcdProbe(appId, uid);
    if (probeUrl.isEmpty) return null;

    try {
      final response = await brandedHttp
          .get(
            Uri.parse(probeUrl),
            headers: {
              'authorization': 'Bearer ${SkyConfig.trackerKey}',
              'accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AttributionTracker] GCD rescue failed: $e');
    }
    return null;
  }
}

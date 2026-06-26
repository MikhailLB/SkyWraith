import 'backend_secrets.dart';
import 'external_urls.dart';
import 'tracker_secrets.dart';

// ============================================================
// SKY CONFIG — Facade over all setup-time constants
// ============================================================
// Single touch-point for every other file in the gray flow.
// Anything that smells like a credential is fetched lazily via
// `reveal()` from `cipher/obfuscator.dart`, so plaintext never
// lives on the heap longer than a single request.
// ============================================================

class SkyConfig {
  // ---- Identity ----
  static const String packageName = 'com.chaosskywrath.skywrath';
  static const String storeListingId = 'com.chaosskywrath.skywrath';
  static const String productName = 'SkyWraith';

  /// iOS-only — App Store numeric ID. Android leaves this blank.
  static const String storeAnalyticsId = '';

  // ---- Endpoints ----
  static String get configEndpoint => unfoldEndpoint();
  static String get privacyUrl => privacyPagePath;
  static String get supportUrl => supportPagePath;
  static String get marketingUrl => marketingPagePath;

  // ---- Credentials ----
  static String get trackerKey => resolveTrackerKey();
  static String get messagingProjectId => resolveMessagingProject();

  // ---- Time budgets (seconds) ----
  static const int promptCooldownSeconds = 3 * 24 * 60 * 60; // 72h
  static const int organicRetryDelaySeconds = 5;
  static const int attributionWaitSeconds = 30;
  static const int returningAttributionTimeoutSeconds = 10;
  static const int deepLinkWaitSeconds = 5;
  static const int configRequestTimeoutSeconds = 15;
  static const int dnsProbeTimeoutSeconds = 7;
  static const int connectivityDebounceMs = 700;

  // ---- Notification channel ----
  /// Must mirror `<meta-data android:value="..."/>` in AndroidManifest.
  static const String pushChannelId = 'sky_wraith_priority_ch';
  static const String pushChannelName = 'Sky Wraith Alerts';
  static const String pushChannelDescription =
      'High priority alerts and Olympian dispatches.';
  static const String pushIconResource = '@drawable/ic_notification';

  // ---- User-Agent identity suffix (Zeus theme rule) ----
  /// Appended after the standard browser UA so the backend can
  /// correlate traffic with this specific binary.
  static String get userAgentSuffix =>
      'appid/$packageName appname/$productName';
}

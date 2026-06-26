import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/launch_mode.dart';

// ============================================================
// PERSISTENCE STORE — Long-lived state for the gray flow
// ============================================================
// Two-tier storage:
//   - SharedPreferences  — flags + timestamps + LaunchMode enum
//   - FlutterSecureStorage — encrypted slot for the resolved
//     portal URL and the one-shot push URL. Sensitive URLs do
//     not belong in plaintext xml under /data/data.
//
// IMPORTANT — the `notification_os_denied` flag:
// Once Android records a "Don't allow" answer on the system
// permission dialog, the OS will never show that dialog again.
// Without persisting that fact the gray flow re-shows the push
// promo every 3 days, the user taps Accept, and nothing
// happens — silent breakage. We persist a hard "OS denied"
// bit and gate the promo on it.
// ============================================================

class PersistenceStore {
  PersistenceStore._();

  factory PersistenceStore() => _instance;
  static final PersistenceStore _instance = PersistenceStore._();

  // The destination URL is intentionally NEVER persisted: every
  // launch must re-query the config endpoint. Only the launch
  // mode hint (portal / arcade) is kept around so an offline
  // returning launch can pick a sane fallback screen.
  static const _kMode = 'launch.mode';
  static const _kPromoCooldownUntil = 'push.promo.cooldown_until';
  static const _kPromoGranted = 'push.promo.granted';
  static const _kPromoOsDenied = 'push.promo.os_denied';
  static const _kInboundPushUrl = 'push.inbound.url';

  late final SharedPreferences _prefs;
  // Default AndroidOptions on flutter_secure_storage 10+ migrate
  // automatically to the new ciphers, so we no longer pass the
  // deprecated encryptedSharedPreferences flag.
  final FlutterSecureStorage _vault = const FlutterSecureStorage();

  Future<void> prime() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ---- Launch mode ----

  LaunchMode readLaunchMode() => LaunchMode.parse(_prefs.getString(_kMode));

  Future<void> writeLaunchMode(LaunchMode mode) =>
      _prefs.setString(_kMode, mode.persist());

  // ---- Push promo cooldown ----

  bool isPromoGranted() => _prefs.getBool(_kPromoGranted) ?? false;
  bool isPromoOsDenied() => _prefs.getBool(_kPromoOsDenied) ?? false;
  int? promoCooldownUntil() => _prefs.getInt(_kPromoCooldownUntil);

  Future<void> markPromoGranted(bool granted) =>
      _prefs.setBool(_kPromoGranted, granted);

  Future<void> markPromoOsDenied() =>
      _prefs.setBool(_kPromoOsDenied, true);

  Future<void> markPromoCooldown(int unixSeconds) =>
      _prefs.setInt(_kPromoCooldownUntil, unixSeconds);

  /// Single source of truth for "show the push promo right now?".
  ///
  /// Three gates, in order of severity:
  ///   1. Already granted? — never show again.
  ///   2. User picked "Don't allow" on the system dialog? — never
  ///      show again either, because requestPermission() will be
  ///      a silent no-op.
  ///   3. Inside the 72h cooldown after a "Skip" tap? — wait.
  bool shouldShowPromo() {
    if (isPromoGranted()) return false;
    if (isPromoOsDenied()) return false;
    final cooldown = promoCooldownUntil();
    if (cooldown == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= cooldown;
  }

  // ---- One-shot inbound push URL (secure) ----

  Future<void> stashPushUrl(String? url) {
    if (url == null || url.isEmpty) {
      return _vault.delete(key: _kInboundPushUrl);
    }
    return _vault.write(key: _kInboundPushUrl, value: url);
  }

  Future<String?> drainPushUrl() async {
    final url = await _vault.read(key: _kInboundPushUrl);
    if (url != null) {
      await _vault.delete(key: _kInboundPushUrl);
    }
    return url;
  }
}

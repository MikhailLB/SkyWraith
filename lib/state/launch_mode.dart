// ============================================================
// LAUNCH MODE — Persistent routing decision for the next session
// ============================================================
// PersistenceStore writes one of these three values after the
// very first config-endpoint roundtrip. From then on the boot
// stage reads this enum and skips the heavy attribution dance.
// ============================================================

enum LaunchMode {
  /// Backend has confirmed paid attribution — go straight to the
  /// WebView portal on next launch.
  portal,

  /// Backend said no — keep the user on the native game from
  /// here on, even if internet becomes available later.
  arcade,

  /// First-ever launch. Run the full attribution + config flow.
  unresolved;

  static LaunchMode parse(String? raw) {
    switch (raw) {
      case 'portal':
        return LaunchMode.portal;
      case 'arcade':
        return LaunchMode.arcade;
      default:
        return LaunchMode.unresolved;
    }
  }

  String persist() {
    switch (this) {
      case LaunchMode.portal:
        return 'portal';
      case LaunchMode.arcade:
        return 'arcade';
      case LaunchMode.unresolved:
        return 'unresolved';
    }
  }
}

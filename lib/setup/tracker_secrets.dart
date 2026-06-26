import '../cipher/obfuscator.dart';

// ============================================================
// TRACKER SECRETS — AppsFlyer + Firebase + GCD endpoint
// ============================================================
// Empty arrays are intentional placeholders. The manager hands
// the real AppsFlyer Dev Key + Firebase project number after
// integration kicks off. Until then `resolveTrackerKey()` and
// `resolveMessagingProject()` both return empty strings — the
// gray flow then short-circuits to the white game so the app
// keeps building and running on a CI device without keys.
//
// To wire them in:
//   1. Fill plaintext values inside tool/encode_keys.dart
//   2. dart run tool/encode_keys.dart
//   3. Replace the byte arrays below with the printed output
// ============================================================

// AppsFlyer Dev Key
const _trackerKeyBytes = <int>[
  0xe0, 0x86, 0x14, 0xfe, 0x24, 0x5e, 0x2f, 0x28, 0x62, 0x95,
  0x82, 0x90, 0xba, 0x5f, 0x26, 0xd2, 0x67, 0xb4, 0xcc, 0x9c,
  0xed, 0xa2,
];

// Firebase project number (sender ID)
const _projectNumberBytes = <int>[
  0xb4, 0xc0, 0x4d, 0xb2, 0x40, 0x04, 0x64, 0x48, 0x2d, 0xd0,
  0xd5, 0x94,
];

// 'https://gcdsdk.appsflyer.com'
const _gcdHostBytes = <int>[
  0xed, 0x86, 0x0e, 0xf7, 0x05, 0x0c, 0x7a, 0x56, 0x7c, 0x83,
  0x80, 0xd0, 0xad, 0x63, 0x4e, 0xda, 0x7a, 0x9e, 0xfd, 0xb7,
  0xe9, 0x8b, 0x1f, 0xf5, 0x58, 0x55, 0x3a, 0x14,
];

// '/install_data/v4.0/'
const _gcdPathBytes = <int>[
  0xaa, 0x9b, 0x14, 0xf4, 0x02, 0x57, 0x39, 0x15, 0x44, 0x84,
  0x85, 0xd7, 0xa8, 0x27, 0x16, 0x8f, 0x24, 0xde, 0xa1,
];

String resolveTrackerKey() {
  if (_trackerKeyBytes.isEmpty) return '';
  return reveal(_trackerKeyBytes);
}

String resolveMessagingProject() {
  if (_projectNumberBytes.isEmpty) return '';
  return reveal(_projectNumberBytes);
}

/// GCD lookup URL — used to retry attribution after a false
/// `af_status: Organic` from the first SDK callback.
///
/// Format:  https://gcdsdk.appsflyer.com/install_data/v4.0/{app}?device_id={uid}
String buildGcdProbe(String appId, String deviceId) {
  if (_gcdHostBytes.isEmpty) return '';
  final base = '${reveal(_gcdHostBytes)}${reveal(_gcdPathBytes)}';
  return '$base$appId?app_id=$appId&device_id=$deviceId';
}

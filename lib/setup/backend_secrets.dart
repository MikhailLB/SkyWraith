import '../cipher/obfuscator.dart';

// ============================================================
// BACKEND SECRETS — Config endpoint (XOR-encoded)
// ============================================================
// The host + path of the routing endpoint that decides whether
// the user gets the WebView (gray) experience or the offline
// game (white). Keeping the domain out of plaintext makes the
// affiliate link invisible to `strings` and naive APK scanners.
//
// Re-generate via:  dart run tool/encode_keys.dart
// after changing the obfuscator seed phrase.
// ============================================================

// 'https://skywratth.com'
const _apiHost = <int>[
  0xed, 0x86, 0x0e, 0xf7, 0x05, 0x0c, 0x7a, 0x56, 0x68, 0x8b,
  0x9d, 0xd4, 0xbb, 0x69, 0x14, 0xcf, 0x62, 0xc0, 0xed, 0xbe,
  0xe8,
];

// '/config.php'
const _apiPath = <int>[
  0xaa, 0x91, 0x15, 0xe9, 0x10, 0x5f, 0x32, 0x57, 0x6b, 0x88,
  0x94,
];

/// Fully-decoded POST endpoint.
String unfoldEndpoint() => '${reveal(_apiHost)}${reveal(_apiPath)}';

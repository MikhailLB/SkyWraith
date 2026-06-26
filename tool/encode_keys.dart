// ignore_for_file: avoid_print
//
// ============================================================
// ENCODE SECRETS — SkyWraith
// ============================================================
// Mirrors lib/cipher/obfuscator.dart exactly. Whenever you rotate
// the seed phrase in obfuscator.dart, copy it here too, then
// re-encode every constant.
//
// Usage:
//   dart run tool/encode_keys.dart
//
// ALWAYS use `dart run`. PowerShell foreach loops overflow 32-bit
// ints on Windows and produce garbage bytes which decode to
// invalid UTF-8 — symptom is `FormatException: Invalid HTTP
// header field value` at first request.
// ============================================================

import 'dart:typed_data';

const _seedPhrase = <int>[
  0x77, 0x72, 0x61, 0x69, 0x74, 0x68, 0x42, 0x6F,
  0x6C, 0x74, 0x21, 0x37, 0x32,
];

Uint8List _buildMask() {
  var lo = 0xC0FFEE;
  var hi = 0xBADBEEF;
  for (final byte in _seedPhrase) {
    final next = (lo + hi + byte) & 0xFFFFFFFFFFFFFFFF;
    lo = hi;
    hi = next;
  }

  var state = (hi ^ (lo << 17)) & 0xFFFFFFFFFFFFFFFF;
  final mask = Uint8List(20);
  for (var i = 0; i < mask.length; i++) {
    state = (state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF;
    var z = state;
    z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF;
    z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF;
    z = (z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF;
    mask[i] = z & 0xFF;
  }
  return mask;
}

final Uint8List _mask = _buildMask();

List<int> encode(String value) {
  final bytes = value.codeUnits;
  final out = List<int>.filled(bytes.length, 0);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ _mask[i % _mask.length];
  }
  return out;
}

String _format(String label, List<int> bytes) {
  final hex = bytes.map((b) => '0x${b.toRadixString(16).padLeft(2, '0')}').join(', ');
  return '// $label\nconst <int>[$hex]';
}

void main() {
  // -------- backend_secrets.dart --------
  const configHost = 'https://skywratth.com';
  const configPath = '/config.php';
  print('// === backend_secrets.dart ===');
  print(_format('apiHost', encode(configHost)));
  print(_format('apiPath', encode(configPath)));
  print('');

  // -------- tracker_secrets.dart --------
  const appsFlyerDevKey = 'etnyRhzQyuf3sWFimZBMhP';
  const firebaseProjectNumber = '127562116017';
  const gcdHost = 'https://gcdsdk.appsflyer.com';
  const gcdPath = '/install_data/v4.0/';

  print('// === tracker_secrets.dart ===');
  print(_format('appsFlyerKey', encode(appsFlyerDevKey)));
  print(_format('messagingProject', encode(firebaseProjectNumber)));
  print(_format('gcdHost', encode(gcdHost)));
  print(_format('gcdPath', encode(gcdPath)));
  print('');

  // -------- branded_http.dart UA fragments --------
  const chromeVer = '132.0.6834.163';
  const webkitVer = '537.36';
  const androidBuild = 'AP3A.240905.015.A2';
  print('// === branded_http.dart ===');
  print(_format('chromeVersion', encode(chromeVer)));
  print(_format('webkitVersion', encode(webkitVer)));
  print(_format('buildTag', encode(androidBuild)));
}

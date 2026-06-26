import 'dart:typed_data';

// ============================================================
// OBFUSCATOR — Per-project string deobfuscator
// ============================================================
// All sensitive constants (config endpoint, AppsFlyer key,
// Firebase project number, Chrome UA tokens) live as bag-of-bytes
// inside the binary. Plaintext never appears in the .so / .dex,
// so trivial `strings | grep` against the APK yields nothing.
//
// The seed phrase below is UNIQUE to SkyWraith. Every project
// in the portfolio must rotate this phrase so the static key
// derived from it does not repeat across binaries. Re-encode
// every byte array via tool/encode_keys.dart after touching it.
//
// Two-stage key derivation:
//   1. Fold the seed bytes with a Fibonacci-style accumulator
//      into a 64-bit integer.
//   2. Drive a SplitMix64-like step to fill a 20-byte stream
//      mask. We use 20 bytes (not 16) so the key cycle does not
//      align with common AES-style block boundaries — extra
//      structural diversity for fingerprint scanners.
// ============================================================

const _seedPhrase = <int>[
  // ASCII for 'wraithBolt!72'
  0x77, 0x72, 0x61, 0x69, 0x74, 0x68, 0x42, 0x6F,
  0x6C, 0x74, 0x21, 0x37, 0x32,
];

Uint8List _buildMask() {
  // Stage 1 — Fibonacci-flavoured fold into a 64-bit integer.
  var lo = 0xC0FFEE;
  var hi = 0xBADBEEF;
  for (final byte in _seedPhrase) {
    final next = (lo + hi + byte) & 0xFFFFFFFFFFFFFFFF;
    lo = hi;
    hi = next;
  }

  // Stage 2 — SplitMix64-style stream to fill 20 bytes.
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

/// Decode a XOR-masked byte list back to UTF-8 text.
/// Pair with `encode()` from tool/encode_keys.dart.
String reveal(List<int> bytes) {
  if (bytes.isEmpty) return '';
  final out = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ _mask[i % _mask.length];
  }
  return String.fromCharCodes(out);
}

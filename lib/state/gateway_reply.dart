// ============================================================
// GATEWAY REPLY — Decoded shape of the config endpoint response
// ============================================================
// Contract negotiated with the backend:
//
//   Portal (gray):
//     { "ok": true,  "url": "https://...", "expires": 1689002181 }
//
//   Arcade (white):
//     { "ok": false, "message": "organic" }
//
// `expires` is a Unix timestamp. The reply itself is never
// persisted: the boot stage queries the endpoint on every
// launch so the destination can change between sessions.
//
// `transportOk` distinguishes "backend gave us a verdict" from
// "transport failed" (timeout / non-200 / malformed JSON). The
// boot stage uses that bit to decide between trusting the
// fresh decision and falling back to the historic LaunchMode.
// ============================================================

class GatewayReply {
  GatewayReply._({
    required this.transportOk,
    required this.ok,
    this.url,
    this.note,
    this.expiresAt,
  });

  /// True when the HTTP roundtrip completed AND the response
  /// body parsed as JSON. False = treat as "no answer".
  final bool transportOk;

  /// Backend verdict (only meaningful when `transportOk`).
  final bool ok;

  final String? url;
  final String? note;
  final int? expiresAt;

  bool get hasUrl => url != null && url!.isNotEmpty;

  factory GatewayReply.fromMap(Map<String, dynamic> map) {
    return GatewayReply._(
      transportOk: true,
      ok: map['ok'] as bool? ?? false,
      url: map['url'] as String?,
      note: map['message'] as String?,
      expiresAt: map['expires'] as int?,
    );
  }

  factory GatewayReply.failed(String reason) =>
      GatewayReply._(transportOk: false, ok: false, note: reason);
}

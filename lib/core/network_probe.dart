import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../setup/sky_config.dart';

// ============================================================
// NETWORK PROBE — "Do we have real internet right now?"
// ============================================================
// connectivity_plus alone is unreliable: a phone on cellular
// with the SIM idle can still report `mobile` and yet not have
// a route, and switching VPN profiles emits a transient
// `[ConnectivityResult.none]` frame that lasts only ms.
//
// Defence in depth:
//   - whitelist *every* interface that can carry traffic,
//     including VPN / bluetooth / "other" tethers,
//   - probe DNS with a 7s timeout (not 3s — VPN tunnels often
//     take >3s on first lookup), and
//   - keep the probe target generic. `cloudflare-dns.com`
//     is preferable to `google.com` because it answers a tiny
//     SOA quickly and is hardly ever ISP-blocked.
// ============================================================

const _liveInterfaces = <ConnectivityResult>{
  ConnectivityResult.wifi,
  ConnectivityResult.mobile,
  ConnectivityResult.ethernet,
  ConnectivityResult.vpn,
  ConnectivityResult.bluetooth,
  ConnectivityResult.other,
};

class NetworkProbe {
  NetworkProbe();

  final Connectivity _conn = Connectivity();

  Stream<List<ConnectivityResult>> get pulse => _conn.onConnectivityChanged;

  Future<bool> hasReachableUplink() async {
    final results = await _conn.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    try {
      final timeout = Duration(seconds: SkyConfig.dnsProbeTimeoutSeconds);
      final lookup =
          await InternetAddress.lookup('cloudflare-dns.com').timeout(timeout);
      if (lookup.isEmpty) return false;
      return lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

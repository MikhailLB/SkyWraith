import 'dart:convert';

import '../setup/sky_config.dart';
import '../state/gateway_reply.dart';
import 'branded_http.dart';

// ============================================================
// CONFIG GATEWAY — POST attribution body, parse decision
// ============================================================
// One responsibility: roundtrip with the routing endpoint and
// return a typed [GatewayReply]. The gateway is stateless on
// purpose — every boot must re-ask the backend, and we never
// cache the resolved URL anywhere.
// ============================================================

class ConfigGateway {
  ConfigGateway();

  Future<GatewayReply> request(Map<String, dynamic> body) async {
    final endpoint = SkyConfig.configEndpoint;
    if (endpoint.isEmpty) {
      return GatewayReply.failed('endpoint-missing');
    }

    final Uri? target = Uri.tryParse(endpoint);
    if (target == null) return GatewayReply.failed('endpoint-malformed');

    try {
      final response = await brandedHttp
          .post(
            target,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            Duration(seconds: SkyConfig.configRequestTimeoutSeconds),
          );

      if (response.statusCode != 200) {
        return GatewayReply.failed('http-${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return GatewayReply.failed('non-json');
      }

      // Intentionally NO URL caching: every launch must re-ask
      // the config endpoint. Caching one URL would freeze the
      // user on a stale link if the backend ever rotates the
      // destination.
      return GatewayReply.fromMap(decoded);
    } catch (e) {
      return GatewayReply.failed(e.toString());
    }
  }
}

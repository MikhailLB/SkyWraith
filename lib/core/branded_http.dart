import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../cipher/obfuscator.dart';
import '../setup/sky_config.dart';

// ============================================================
// BRANDED HTTP — User-Agent identity for every outbound request
// ============================================================
// Two design goals:
//
//   1. Look like a real Chrome on Android device, not Dart's
//      default "Dart/X.Y (dart:io)". Naive backends fingerprint
//      requests on UA and reject anything that isn't a browser.
//
//   2. Make traffic from this binary attributable WITHOUT a
//      cookie. The Zeus/Magma project rule appends the package
//      id + a space-free app name token to the UA, so the
//      backend can correlate config calls with the binary that
//      issued them. The same suffix has to be used by the
//      WebView (PortalStage.setUserAgent) — see SkyConfig.
//
// Chrome / WebKit / Android build tokens live as XOR-masked
// byte arrays so trivial APK scanning doesn't surface "Chrome
// 132" strings out of the binary.
// ============================================================

// '132.0.6834.163'
const _chromeBytes = <int>[
  0xb4, 0xc1, 0x48, 0xa9, 0x46, 0x18, 0x63, 0x41, 0x28, 0xd4,
  0xca, 0x92, 0xff, 0x3b,
];

// '537.36'
const _webkitBytes = <int>[
  0xb0, 0xc1, 0x4d, 0xa9, 0x45, 0x00,
];

// 'AP3A.240905.015.A2'
const _buildBytes = <int>[
  0xc4, 0xa2, 0x49, 0xc6, 0x58, 0x04, 0x61, 0x49, 0x22, 0xd0,
  0xd1, 0x8d, 0xf9, 0x39, 0x55, 0x95, 0x4b, 0xdc,
];

String get _chromeVersion => reveal(_chromeBytes);
String get _webkitVersion => reveal(_webkitBytes);
String get _buildFallback => reveal(_buildBytes);

class BrandedHttpClient extends http.BaseClient {
  BrandedHttpClient._();

  final http.Client _delegate = http.Client();
  String? _userAgent;

  Future<void> prime() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final sdk = info.version.sdkInt;
        final model = info.model;
        final brand = info.brand;
        final build = info.display.isNotEmpty
            ? info.display
            : (info.id.isNotEmpty ? info.id : _buildFallback);
        final chrome =
            _chromeVersion.isNotEmpty ? _chromeVersion : '132.0.6834.163';
        final webkit = _webkitVersion.isNotEmpty ? _webkitVersion : '537.36';
        _userAgent =
            'Mozilla/5.0 (Linux; Android $sdk; $brand $model Build/$build) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Chrome/$chrome Mobile Safari/$webkit '
            '${SkyConfig.userAgentSuffix}';
      } else {
        final info = await plugin.iosInfo;
        final ver = info.systemVersion.replaceAll('.', '_');
        final webkit = _webkitVersion.isNotEmpty ? _webkitVersion : '537.36';
        _userAgent =
            'Mozilla/5.0 (iPhone; CPU iPhone OS $ver like Mac OS X) '
            'AppleWebKit/$webkit (KHTML, like Gecko) '
            'Version/${info.systemVersion} Mobile/15E148 Safari/$webkit '
            '${SkyConfig.userAgentSuffix}';
      }
    } catch (_) {
      final chrome =
          _chromeVersion.isNotEmpty ? _chromeVersion : '132.0.6834.163';
      final webkit = _webkitVersion.isNotEmpty ? _webkitVersion : '537.36';
      _userAgent = Platform.isAndroid
          ? 'Mozilla/5.0 (Linux; Android 15; SM-S931U Build/$_buildFallback) '
              'AppleWebKit/$webkit (KHTML, like Gecko) '
              'Chrome/$chrome Mobile Safari/$webkit '
              '${SkyConfig.userAgentSuffix}'
          : 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
              'AppleWebKit/$webkit (KHTML, like Gecko) '
              'Version/17.0 Mobile/15E148 Safari/$webkit '
              '${SkyConfig.userAgentSuffix}';
    }
  }

  String get currentUserAgent => _userAgent ?? 'Mozilla/5.0';

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.putIfAbsent('User-Agent', () => currentUserAgent);
    return _delegate.send(request);
  }

  @override
  void close() => _delegate.close();
}

/// Process-wide singleton shared by every gray-flow service so
/// the User-Agent string is built exactly once per launch.
final brandedHttp = BrandedHttpClient._();

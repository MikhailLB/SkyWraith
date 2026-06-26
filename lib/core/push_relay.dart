import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../setup/sky_config.dart';
import 'branded_http.dart';
import 'persistence_store.dart';

// ============================================================
// PUSH RELAY — FCM + local notifications + URL routing
// ============================================================
// Three tap scenarios that the spec treats differently:
//
//   COLD start (app killed when tap happens):
//     FirebaseMessaging.getInitialMessage() fires once at boot.
//     We *persist* the URL — SplashScreen will read it via
//     drainPushUrl() on the very next launch and route there.
//
//   WARM background tap:
//     onMessageOpenedApp delivers the message. We hand the URL
//     to the live callback (PortalStage). DO NOT persist —
//     spec says push URLs are one-shot.
//
//   FOREGROUND arrival:
//     onMessage fires. We show a local notification with the
//     custom flame icon; tapping it goes through
//     onDidReceiveNotificationResponse, which delivers the URL
//     via the same live callback. Again, no persistence.
//
// If Firebase initialisation throws (missing google-services or
// AppCheck not enabled in debug), we swallow the error and the
// app continues without push. Spec says push is best-effort.
// ============================================================

@pragma('vm:entry-point')
Future<void> _backgroundEntry(RemoteMessage _) async {
  // Empty by design — Android handles the system tray, and
  // the actual URL tap is delivered via getInitialMessage()
  // or onMessageOpenedApp once the user resumes the app.
}

class PushRelay {
  PushRelay(this._store);

  final PersistenceStore _store;
  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _messaging;
  String? _token;
  bool _ready = false;

  /// Live URL callback. PortalStage subscribes for warm taps.
  void Function(String url)? onLiveUrl;

  /// FCM token rotation hook. SplashScreen re-posts on rotate.
  void Function(String token)? onTokenRotate;

  String? get token => _token;

  Future<void> awaken() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;

      FirebaseMessaging.onBackgroundMessage(_backgroundEntry);

      await _setupLocalChannel();

      _token = await _messaging!.getToken();
      _messaging!.onTokenRefresh.listen((next) {
        _token = next;
        onTokenRotate?.call(next);
      });

      FirebaseMessaging.onMessage.listen(_handleForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(_handleWarmTap);

      final coldStartMessage = await _messaging!.getInitialMessage();
      if (coldStartMessage != null) await _handleColdTap(coldStartMessage);

      _ready = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[PushRelay] init skipped: $e');
    }
  }

  Future<bool> requestSystemPermission() async {
    if (_messaging == null) {
      await _store.markPromoOsDenied();
      return false;
    }
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final status = settings.authorizationStatus;
    final granted = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    if (granted) {
      await _store.markPromoGranted(true);
    } else if (status == AuthorizationStatus.denied) {
      // OS will refuse subsequent requestPermission() calls.
      await _store.markPromoOsDenied();
    }
    return granted;
  }

  // ------------- internals -------------

  Future<void> _setupLocalChannel() async {
    const androidSettings =
        AndroidInitializationSettings(SkyConfig.pushIconResource);
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localPlugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == null) return;
        try {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          final url = data['url'];
          if (url is String && url.isNotEmpty) onLiveUrl?.call(url);
        } catch (_) {}
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin =
          _localPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          SkyConfig.pushChannelId,
          SkyConfig.pushChannelName,
          description: SkyConfig.pushChannelDescription,
          importance: Importance.high,
        ),
      );
    }
  }

  Future<void> _handleForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (!Platform.isAndroid) return; // iOS shows its own banner.

    final imageUrl = message.notification?.android?.imageUrl;
    AndroidNotificationDetails? details;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final bytes = await _downloadBytes(imageUrl);
      if (bytes != null) {
        details = AndroidNotificationDetails(
          SkyConfig.pushChannelId,
          SkyConfig.pushChannelName,
          channelDescription: SkyConfig.pushChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: SkyConfig.pushIconResource,
          styleInformation: BigPictureStyleInformation(
            ByteArrayAndroidBitmap(bytes),
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        );
      }
    }
    details ??= AndroidNotificationDetails(
      SkyConfig.pushChannelId,
      SkyConfig.pushChannelName,
      channelDescription: SkyConfig.pushChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: SkyConfig.pushIconResource,
    );

    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;
    await _localPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(android: details),
      payload: payload,
    );
  }

  Future<void> _handleColdTap(RemoteMessage message) async {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) {
      await _store.stashPushUrl(url);
    }
  }

  void _handleWarmTap(RemoteMessage message) {
    final url = message.data['url'];
    if (url is String && url.isNotEmpty) onLiveUrl?.call(url);
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final response = await brandedHttp
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }
}

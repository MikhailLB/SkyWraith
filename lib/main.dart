import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/attribution_tracker.dart';
import 'core/branded_http.dart';
import 'core/config_gateway.dart';
import 'core/network_probe.dart';
import 'core/persistence_store.dart';
import 'core/push_relay.dart';
import 'gray/boot_stage.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase + App Check. Both throw if google-services.json is
  // missing, which is fine during initial scaffolding — the gray
  // flow degrades to the offline game without push.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } catch (_) {}

  // Boot screen needs both orientations; the arcade locks to
  // portrait once it takes over via LoadingScreen._goToMenu().
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: SkyColors.deepNavy,
    ),
  );

  await brandedHttp.prime();

  final store = PersistenceStore();
  await store.prime();

  final probe = NetworkProbe();
  final tracker = AttributionTracker();
  final gateway = ConfigGateway();
  final relay = PushRelay(store);

  runApp(SkyWraithApp(
    store: store,
    probe: probe,
    tracker: tracker,
    gateway: gateway,
    relay: relay,
  ));
}

class SkyWraithApp extends StatelessWidget {
  const SkyWraithApp({
    super.key,
    required this.store,
    required this.probe,
    required this.tracker,
    required this.gateway,
    required this.relay,
  });

  final PersistenceStore store;
  final NetworkProbe probe;
  final AttributionTracker tracker;
  final ConfigGateway gateway;
  final PushRelay relay;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sky Wraith',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: BootStage(
        store: store,
        probe: probe,
        tracker: tracker,
        gateway: gateway,
        relay: relay,
      ),
    );
  }
}

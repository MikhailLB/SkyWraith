import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow both orientations during the loading screen. The rest of the game is
  // locked to portrait once loading finishes (see LoadingScreen).
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: SkyColors.deepNavy,
    ),
  );
  runApp(const SkyWraithApp());
}

class SkyWraithApp extends StatelessWidget {
  const SkyWraithApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sky Wraith',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const LoadingScreen(),
    );
  }
}

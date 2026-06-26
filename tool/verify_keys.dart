// ignore_for_file: avoid_print, avoid_relative_lib_imports
//
// One-shot smoke test that confirms the byte arrays committed
// into lib/setup/*.dart decode back to the expected plaintext.
// Run with:  dart run tool/verify_keys.dart

import '../lib/cipher/obfuscator.dart';
import '../lib/setup/backend_secrets.dart';
import '../lib/setup/tracker_secrets.dart';

void main() {
  final endpoint = unfoldEndpoint();
  final trackerKey = resolveTrackerKey();
  final messagingProject = resolveMessagingProject();
  final gcdProbe = buildGcdProbe('com.example', 'fake-uid');

  print('endpoint=$endpoint');
  print('trackerKey=$trackerKey');
  print('messagingProject=$messagingProject');
  print('gcdProbe=$gcdProbe');

  // Touch reveal() so the analyzer doesn't drop the import.
  reveal(const <int>[]);
}

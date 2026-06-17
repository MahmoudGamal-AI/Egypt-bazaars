// File generated manually - replace with `flutterfire configure` output
// This is a placeholder file. Run `flutterfire configure` to generate the actual file.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase configuration options for the current platform.
///
/// IMPORTANT: This is a placeholder file. You need to:
/// 1. Install FlutterFire CLI: `dart pub global activate flutterfire_cli`
/// 2. Run: `flutterfire configure`
/// 3. Select your Firebase project
/// 4. This file will be replaced with actual configuration
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // TODO: Replace these placeholder values with your actual Firebase configuration
  // Run `flutterfire configure` to generate the correct values

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: '1:PLACEHOLDER
    messagingSenderId: 'PLACEHOLDER
    projectId: 'egyptian-tourism-app',
    authDomain: 'egyptian-tourism-app.firebaseapp.com',
    storageBucket: 'egyptian-tourism-app.firebasestorage.app',
    measurementId: 'G-9CLQM5EYJ5',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: '1:PLACEHOLDER
    messagingSenderId: 'PLACEHOLDER
    projectId: 'egyptian-tourism-app',
    storageBucket: 'egyptian-tourism-app.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: '1:PLACEHOLDER
    messagingSenderId: 'PLACEHOLDER
    projectId: 'egyptian-tourism-app',
    storageBucket: 'egyptian-tourism-app.firebasestorage.app',
    iosClientId:
        'PLACEHOLDER
    iosBundleId: 'com.egyptiantourism.egyptianTourismApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: '1:PLACEHOLDER
    messagingSenderId: 'PLACEHOLDER
    projectId: 'egyptian-tourism-app',
    storageBucket: 'egyptian-tourism-app.firebasestorage.app',
    iosClientId:
        'PLACEHOLDER
    iosBundleId: 'com.egyptiantourism.egyptianTourismApp',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: '1:PLACEHOLDER
    messagingSenderId: 'PLACEHOLDER
    projectId: 'egyptian-tourism-app',
    authDomain: 'egyptian-tourism-app.firebaseapp.com',
    storageBucket: 'egyptian-tourism-app.firebasestorage.app',
    measurementId: 'G-KXVYK4JY2Q',
  );
}

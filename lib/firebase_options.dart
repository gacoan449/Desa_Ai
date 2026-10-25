// Generated Firebase options placeholder.
// Run "flutterfire configure --project PROJECT_ID" to replace this file with your real project values.
// Firebase client options are not server secrets; never place OpenAI/TriPay private keys here.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Desa AI is configured for Android and Web. Run FlutterFire configure for another platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_WEB_API_KEY',
    appId: '1:000000000000:web:replace_me',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
    authDomain: 'replace-with-firebase-project-id.firebaseapp.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FIREBASE_ANDROID_API_KEY',
    appId: '1:000000000000:android:replace_me',
    messagingSenderId: '000000000000',
    projectId: 'replace-with-firebase-project-id',
  );
}

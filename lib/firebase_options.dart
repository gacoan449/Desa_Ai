// Firebase client configuration for the Desa AI Android app.
// These values identify the Firebase app; keep OpenAI and TriPay secrets on the server.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Firebase Web options have not been configured for Desa AI.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Desa AI is configured for Android only.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCCoStDl2BPu2WapQI8WWXm5NEKwRmVDko',
    appId: '1:295144083758:android:f73fff4b4d7fc8ef7feabf',
    messagingSenderId: '295144083758',
    projectId: 'desaai-dfe30',
    storageBucket: 'desaai-dfe30.firebasestorage.app',
  );
}

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static final AppConfig instance = AppConfig._();
  AppConfig._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  String? _get(String key) => dotenv.env[key];

  String _req(String key) {
    final v = _get(key);
    if (v == null || v.isEmpty) {
      throw Exception('مفقود: $key في ملف .env');
    }
    return v;
  }

  String get serverClientId => _req('GOOGLE_SERVER_CLIENT_ID');

  FirebaseOptions get firebaseOptions {
    if (kIsWeb) return _webOptions;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidOptions;
      case TargetPlatform.iOS:
        return _iosOptions;
      case TargetPlatform.macOS:
        return _macosOptions;
      case TargetPlatform.windows:
        return _windowsOptions;
      default:
        throw UnsupportedError('المنصة غير مدعومة');
    }
  }

  FirebaseOptions get _webOptions => FirebaseOptions(
    apiKey: _req('FIREBASE_WEB_API_KEY'),
    appId: _req('FIREBASE_WEB_APP_ID'),
    messagingSenderId: _req('FIREBASE_WEB_MESSAGING_SENDER_ID'),
    projectId: _req('FIREBASE_PROJECT_ID'),
    authDomain: _req('FIREBASE_WEB_AUTH_DOMAIN'),
    databaseURL: _req('FIREBASE_WEB_DATABASE_URL'),
    storageBucket: _req('FIREBASE_WEB_STORAGE_BUCKET'),
  );

  FirebaseOptions get _androidOptions => FirebaseOptions(
    apiKey: _req('FIREBASE_ANDROID_API_KEY'),
    appId: _req('FIREBASE_ANDROID_APP_ID'),
    messagingSenderId: _req('FIREBASE_WEB_MESSAGING_SENDER_ID'),
    projectId: _req('FIREBASE_PROJECT_ID'),
    databaseURL: _req('FIREBASE_DATABASE_URL'),
    storageBucket: _req('FIREBASE_STORAGE_BUCKET'),
    androidClientId: _req('FIREBASE_ANDROID_CLIENT_ID'),
  );

  FirebaseOptions get _iosOptions => FirebaseOptions(
    apiKey: _req('FIREBASE_IOS_API_KEY'),
    appId: _req('FIREBASE_IOS_APP_ID'),
    messagingSenderId: _req('FIREBASE_WEB_MESSAGING_SENDER_ID'),
    projectId: _req('FIREBASE_PROJECT_ID'),
    databaseURL: _req('FIREBASE_DATABASE_URL'),
    storageBucket: _req('FIREBASE_STORAGE_BUCKET'),
    androidClientId: _req('FIREBASE_ANDROID_CLIENT_ID'),
    iosClientId: _req('FIREBASE_IOS_CLIENT_ID'),
    iosBundleId: _req('FIREBASE_IOS_BUNDLE_ID'),
  );

  FirebaseOptions get _macosOptions => FirebaseOptions(
    apiKey: _req('FIREBASE_IOS_API_KEY'),
    appId: _req('FIREBASE_IOS_APP_ID'),
    messagingSenderId: _req('FIREBASE_WEB_MESSAGING_SENDER_ID'),
    projectId: _req('FIREBASE_PROJECT_ID'),
    databaseURL: _req('FIREBASE_DATABASE_URL'),
    storageBucket: _req('FIREBASE_STORAGE_BUCKET'),
    androidClientId: _req('FIREBASE_ANDROID_CLIENT_ID'),
    iosClientId: _req('FIREBASE_MACOS_CLIENT_ID'),
    iosBundleId: _req('FIREBASE_IOS_BUNDLE_ID'),
  );

  FirebaseOptions get _windowsOptions => FirebaseOptions(
    apiKey: _req('FIREBASE_WEB_API_KEY'),
    appId: _req('FIREBASE_WINDOWS_APP_ID'),
    messagingSenderId: _req('FIREBASE_WEB_MESSAGING_SENDER_ID'),
    projectId: _req('FIREBASE_PROJECT_ID'),
    authDomain: _req('FIREBASE_WEB_AUTH_DOMAIN'),
    databaseURL: _req('FIREBASE_WEB_DATABASE_URL'),
    storageBucket: _req('FIREBASE_WEB_STORAGE_BUCKET'),
  );
}

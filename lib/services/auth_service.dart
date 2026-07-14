import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../app_config.dart';

class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: AppConfig.instance.serverClientId,
  );

  String? _lastError;
  String? get lastError => _lastError;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  GoogleSignInAccount? get currentGoogleAccount => _googleSignIn.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      _lastError = null;
      GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      var credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      try {
        return await _auth.signInWithCredential(credential);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'invalid-credential') {
          await _googleSignIn.disconnect();
          googleUser = await _googleSignIn.signIn();
          if (googleUser == null) return null;
          googleAuth = await googleUser.authentication;
          credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          return await _auth.signInWithCredential(credential);
        }
        rethrow;
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('stale') || msg.contains('ID Token issued at')) {
        _lastError = 'تاريخ ووقت الجهاز غير صحيح. يرجى ضبط الساعة تلقائياً من الإعدادات';
      } else {
        _lastError = msg;
      }
      return null;
    }
  }

  Future<GoogleSignInAccount?> trySilentSignIn() async {
    try {
      _lastError = null;
      return await _googleSignIn.signInSilently();
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<GoogleSignInAccount?> signInGoogle() async {
    try {
      _lastError = null;
      return await _googleSignIn.signIn();
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<bool> requestDriveScope() async {
    try {
      _lastError = null;
      return await _googleSignIn.requestScopes(
        ['https://www.googleapis.com/auth/drive.file'],
      );
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  Future<String?> getAccessToken() async {
    try {
      _lastError = null;
      var account = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

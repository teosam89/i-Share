import 'package:firebase_auth/firebase_auth.dart';
import '../core/admin_constants.dart';

class AdminAuthService {
  static final _auth = FirebaseAuth.instance;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  static bool get isCurrentUserAdmin =>
      AdminConstants.isAdmin(_auth.currentUser?.uid);

  static Future<UserCredential> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  static Future<void> signOut() => _auth.signOut();
}

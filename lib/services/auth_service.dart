import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';

abstract class AuthService {
  String? get uid;
  Stream<String?> get sessions;
  Future<void> login(String email, String password);
  Future<void> register(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> logout();
  Future<String?> token(bool forceRefresh);
}

String authMessage(FirebaseAuthException error) => switch (error.code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'Correo o contraseña incorrectos.',
  'email-already-in-use' => 'Ya hay una cuenta con este correo.',
  'invalid-email' => 'El correo no es válido.',
  'weak-password' => 'La contraseña es demasiado débil.',
  'user-disabled' => 'Esta cuenta está deshabilitada.',
  'too-many-requests' => 'Demasiados intentos. Esperá unos minutos.',
  'network-request-failed' =>
    'No se pudo conectar con Firebase. Revisá Internet.',
  'operation-not-allowed' =>
    'Habilitá Email/Password en Firebase Authentication.',
  _ => 'No se pudo completar la autenticación. Revisá la configuración de Firebase.',
};

class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this.firebase);
  final FirebaseAuth firebase;
  @override
  String? get uid => firebase.currentUser?.uid;
  @override
  Stream<String?> get sessions =>
      firebase.authStateChanges().map((u) => u?.uid);
  Future<void> _perform(Future<dynamic> Function() operation) async {
    try {
      await operation();
    } on FirebaseAuthException catch (e) {
      throw ApiException(authMessage(e));
    }
  }

  @override
  Future<void> login(String email, String password) => _perform(
    () => firebase.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );
  @override
  Future<void> register(String email, String password) => _perform(
    () => firebase.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    ),
  );
  @override
  Future<void> resetPassword(String email) =>
      _perform(() => firebase.sendPasswordResetEmail(email: email.trim()));
  @override
  Future<void> logout() => _perform(firebase.signOut);
  @override
  Future<String?> token(bool forceRefresh) async {
    try {
      return await firebase.currentUser?.getIdToken(forceRefresh);
    } on FirebaseAuthException catch (e) {
      throw ApiException(authMessage(e), status: 401);
    }
  }
}

import 'package:firebase_core/firebase_core.dart';

Future<FirebaseApp> initializeFirebase() {
  const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  const appId = String.fromEnvironment('FIREBASE_APP_ID');
  const senderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  final values = [apiKey, appId, senderId, projectId];
  if (values.any((v) => v.isNotEmpty) && values.any((v) => v.isEmpty)) {
    throw StateError(
      'Completá los cuatro valores FIREBASE_* en config/firebase.json.',
    );
  }
  return Firebase.initializeApp(
    options: values.every((v) => v.isNotEmpty)
        ? const FirebaseOptions(
            apiKey: apiKey,
            appId: appId,
            messagingSenderId: senderId,
            projectId: projectId,
          )
        : null,
  );
}

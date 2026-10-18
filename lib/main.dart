import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'app.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/firebase_config.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  String? _error;
  AuthService? _auth;
  ApiClient? _api;
  NotificationService? _notifications;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _error = null;
    });
    try {
      await initializeFirebase();
      final auth = FirebaseAuthService(FirebaseAuth.instance);
      final api = ApiClient(
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:8000/api/v1',
        ),
        tokenProvider: auth.token,
      );
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessage);
      final notifications = NotificationService(auth, api);
      await notifications.initialize();
      if (!mounted) {
        api.close();
        await notifications.dispose();
        return;
      }
      setState(() {
        _auth = auth;
        _api = api;
        _notifications = notifications;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo iniciar Firebase o la API. Configurá Android en Firebase y completá config/firebase.json siguiendo docs/INSTALACION_WINDOWS.md. La URL de la API debe terminar en /api/v1; producción requiere HTTPS. No uses credenciales Firebase Admin en Flutter.';
        });
      }
    }
  }

  @override
  void dispose() {
    _api?.close();
    _notifications?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_auth != null) {
      return ClubApp(auth: _auth!, api: _api!, notifications: _notifications);
    }
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('ClubNestorArakaki')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _initialize,
                        child: const Text('Reintentar configuración'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

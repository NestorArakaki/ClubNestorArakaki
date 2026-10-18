import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'firebase_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessage(RemoteMessage message) async {
  await initializeFirebase();
  // Android presenta el notification payload. No se navega desde este isolate.
}

class PushTarget {
  const PushTarget(this.bookingId, this.uid);
  final int bookingId;
  final String uid;
  static PushTarget? parse(Map<String, dynamic> data) {
    final id = int.tryParse('${data['booking_id']}');
    final uid = data['recipient_uid'];
    if (id == null ||
        id <= 0 ||
        uid is! String ||
        ![
          'booking_created',
          'booking_cancelled',
          'booking_reminder',
        ].contains(data['type'])) {
      return null;
    }
    return PushTarget(id, uid);
  }
}

class NotificationService with WidgetsBindingObserver {
  NotificationService(this.auth, this.api);
  final AuthService auth;
  final ApiClient api;
  final target = ValueNotifier<PushTarget?>(null);
  final status = ValueNotifier<String>('Notificaciones sin activar.');
  final _local = FlutterLocalNotificationsPlugin();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _initialized = false, _unlinking = false, _initializing = false;
  String? _registeredUid, _registeredToken;

  Future<void> initialize() async {
    if (_initializing || _initialized) return;
    _initializing = true;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      const android = AndroidInitializationSettings('ic_stat_booking');
      await _local.initialize(
        const InitializationSettings(android: android),
        onDidReceiveNotificationResponse: (response) {
          try {
            target.value = PushTarget.parse(
              jsonDecode(response.payload ?? '{}') as Map<String, dynamic>,
            );
          } on FormatException {
            /* Payload inválido: no abre rutas arbitrarias. */
          }
        },
      );
      const channel = AndroidNotificationChannel(
        'bookings',
        'Reservas',
        description: 'Confirmaciones y cancelaciones de reservas',
        importance: Importance.high,
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        target.value = PushTarget.parse(
          jsonDecode(launch!.notificationResponse?.payload ?? '{}')
              as Map<String, dynamic>,
        );
      }
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen((message) {
          if (auth.uid != message.data['recipient_uid']) return;
          final notice = message.notification;
          if (notice != null) {
            unawaited(
              _local
                  .show(
                    message.hashCode,
                    notice.title,
                    notice.body,
                    const NotificationDetails(
                      android: AndroidNotificationDetails(
                        'bookings',
                        'Reservas',
                        icon: 'ic_stat_booking',
                        importance: Importance.high,
                        priority: Priority.high,
                      ),
                    ),
                    payload: jsonEncode(message.data),
                  )
                  .catchError((Object _) {}),
            );
          }
        }),
      );
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen((m) {
          target.value = PushTarget.parse(m.data);
        }),
      );
      _subscriptions.add(
        FirebaseMessaging.instance.onTokenRefresh.listen(
          (_) {
            unawaited(sync());
          },
          onError: (Object _) {
            status.value = 'No se pudo actualizar el token. Reintentá con “Activar avisos”.';
          },
        ),
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) target.value = PushTarget.parse(initial.data);
      _initialized = true;
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      status.value = 'No se pudieron iniciar las notificaciones. Podés usar las reservas normalmente.';
    } finally {
      _initializing = false;
    }
  }

  Future<void> sync({bool requestPermission = false}) async {
    if (!_initialized && requestPermission) await initialize();
    if (!_initialized || _unlinking || auth.uid == null) return;
    final owner = auth.uid;
    try {
      final settings = requestPermission
          ? await FirebaseMessaging.instance.requestPermission()
          : await FirebaseMessaging.instance.getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        status.value =
            'Activá los permisos de notificaciones para recibir avisos.';
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || auth.uid != owner) return;
      if (_registeredToken != token || _registeredUid != owner) {
        await api.registerDevice(token);
        if (auth.uid != owner) return;
        _registeredToken = token;
        _registeredUid = owner;
      }
      status.value = 'Dispositivo registrado para recibir avisos.';
    } catch (_) {
      status.value = 'No se pudo registrar el dispositivo. Reintentá con “Activar avisos”.';
    }
  }

  Future<void> unlink() async {
    _unlinking = true;
    // Logout sigue disponible aun si la API está caída. Se invalida el token en FCM.
    try {
      final token = await FirebaseMessaging.instance.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (token != null) {
        await api.unregisterDevice(token).timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      /* Se intenta invalidar también el registro del proveedor. */
    }
    try {
      await FirebaseMessaging.instance.deleteToken().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    try {
      await _local.cancelAll();
    } catch (_) {}
    _registeredUid = null;
    _registeredToken = null;
    target.value = null;
    _unlinking = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    target.dispose();
    status.dispose();
  }
}

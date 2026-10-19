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

enum NotificationPhase {
  inactive,
  checking,
  permissionRequired,
  enabled,
  error,
}

class NotificationStatus {
  const NotificationStatus(this.phase, this.message);
  final NotificationPhase phase;
  final String message;
}

class NotificationService with WidgetsBindingObserver {
  NotificationService(
    this.auth,
    this.api, {
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _firebaseMessaging = messaging,
       _local = localNotifications ?? FlutterLocalNotificationsPlugin();
  final AuthService auth;
  final ApiClient api;
  final target = ValueNotifier<PushTarget?>(null);
  final status = ValueNotifier<NotificationStatus>(
    const NotificationStatus(
      NotificationPhase.inactive,
      'Notificaciones sin activar.',
    ),
  );
  final FirebaseMessaging? _firebaseMessaging;
  FirebaseMessaging get _messaging =>
      _firebaseMessaging ?? FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _initialized = false, _unlinking = false, _initializing = false;
  bool _syncing = false, _syncAgain = false, _disposed = false;
  int _sessionRevision = 0;
  String? _registeredUid, _registeredToken;

  void _setStatus(NotificationPhase phase, String message) {
    if (!_disposed) status.value = NotificationStatus(phase, message);
  }

  Future<void> initialize() async {
    if (_initializing || _initialized || _disposed) return;
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
        _messaging.onTokenRefresh.listen(
          (_) {
            if (_syncing) {
              _syncAgain = true;
            } else {
              unawaited(sync());
            }
          },
          onError: (Object _) {
            _setStatus(
              NotificationPhase.error,
              'No se pudo actualizar el token. Reintentá activar los avisos.',
            );
          },
        ),
      );
      final initial = await _messaging.getInitialMessage();
      if (_disposed) return;
      if (initial != null) target.value = PushTarget.parse(initial.data);
      _initialized = true;
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      _setStatus(
        NotificationPhase.error,
        'No se pudieron iniciar las notificaciones. Podés usar las reservas normalmente.',
      );
    } finally {
      _initializing = false;
    }
  }

  Future<void> sync({bool requestPermission = false}) async {
    if (_syncing || _unlinking || _disposed) return;
    final owner = auth.uid;
    if (owner == null) return;
    final revision = _sessionRevision;
    bool isCurrent() =>
        !_disposed &&
        !_unlinking &&
        auth.uid == owner &&
        revision == _sessionRevision;
    _syncing = true;
    try {
      if (_initialized || requestPermission) {
        _setStatus(
          NotificationPhase.checking,
          'Comprobando permisos y registro de notificaciones…',
        );
      }
      if (!_initialized && requestPermission) await initialize();
      if (!_initialized || !isCurrent()) return;
      final settings = requestPermission
          ? await _messaging.requestPermission()
          : await _messaging.getNotificationSettings();
      if (!isCurrent()) return;
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        _setStatus(
          NotificationPhase.permissionRequired,
          'Activá los permisos de notificaciones. Si Android no vuelve a pedirlos, habilitalos en Ajustes y volvé a la app.',
        );
        return;
      }
      final token = await _messaging.getToken();
      if (!isCurrent()) return;
      if (token == null || token.isEmpty) {
        _setStatus(
          NotificationPhase.error,
          'No se pudo obtener el token del dispositivo. Reintentá activar los avisos.',
        );
        return;
      }
      if (_registeredToken != token || _registeredUid != owner) {
        await api.registerDevice(token);
        if (!isCurrent()) return;
        _registeredToken = token;
        _registeredUid = owner;
      }
      // Habilitación verificada; no confirma la entrega de ningún mensaje.
      _setStatus(NotificationPhase.enabled, 'Notificaciones activadas');
    } catch (_) {
      if (isCurrent()) {
        _setStatus(
          NotificationPhase.error,
          'No se pudo registrar el dispositivo. Reintentá activar los avisos.',
        );
      }
    } finally {
      _syncing = false;
      if (_syncAgain && !_disposed) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  Future<void> unlink() async {
    _unlinking = true;
    _sessionRevision++;
    _syncAgain = false;
    _setStatus(NotificationPhase.inactive, 'Notificaciones sin activar.');
    // Logout sigue disponible aun si la API está caída. Se invalida el token en FCM.
    try {
      final token = await _messaging.getToken().timeout(
        const Duration(seconds: 5),
      );
      if (token != null) {
        await api.unregisterDevice(token).timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      /* Se intenta invalidar también el registro del proveedor. */
    }
    try {
      await _messaging.deleteToken().timeout(const Duration(seconds: 5));
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
    if (state == AppLifecycleState.resumed) {
      if (_syncing) {
        _syncAgain = true;
      } else {
        unawaited(sync());
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    target.dispose();
    status.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:club_nestor_arakaki/app.dart';
import 'package:club_nestor_arakaki/services/api_client.dart';
import 'package:club_nestor_arakaki/services/auth_service.dart';
import 'package:club_nestor_arakaki/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class NotificationAuth implements AuthService {
  @override
  String? get uid => 'alice';
  @override
  Future<String?> token(bool forceRefresh) async => 'test-token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettings implements NotificationSettings {
  TestSettings(this.authorizationStatus);
  @override
  final AuthorizationStatus authorizationStatus;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestMessaging implements FirebaseMessaging {
  AuthorizationStatus permission = AuthorizationStatus.authorized;
  String? token = 'fcm-token';
  bool failSettings = false, failToken = false;
  int permissionRequests = 0, settingsReads = 0;
  final tokens = StreamController<String>.broadcast();

  @override
  Stream<String> get onTokenRefresh => tokens.stream;
  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<NotificationSettings> getNotificationSettings() async {
    settingsReads++;
    if (failSettings) throw Exception('settings unavailable');
    return TestSettings(permission);
  }

  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) async {
    permissionRequests++;
    return getNotificationSettings();
  }

  @override
  Future<String?> getToken({
    String? vapidKey,
    String? serviceWorkerScriptPath,
  }) async {
    if (failToken) throw Exception('FCM unavailable');
    return token;
  }

  @override
  Future<void> deleteToken() async => token = null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestLocalNotifications implements FlutterLocalNotificationsPlugin {
  bool failInitialize = false;
  int displayed = 0;
  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    if (failInitialize) throw Exception('initialization failed');
    return true;
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() => null;
  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => null;
  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    displayed++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestMessaging messaging;
  late TestLocalNotifications local;
  late ApiClient api;
  late NotificationService service;
  late NotificationAuth auth;
  late int registrations;
  late List<Object?> registeredBodies;
  late bool failRegistration;
  Completer<http.Response>? pendingRegistration;

  setUp(() {
    messaging = TestMessaging();
    local = TestLocalNotifications();
    auth = NotificationAuth();
    registrations = 0;
    registeredBodies = [];
    failRegistration = false;
    pendingRegistration = null;
    api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: auth.token,
      client: MockClient((request) async {
        if (request.method == 'POST' && request.url.path.endsWith('/devices')) {
          registrations++;
          registeredBodies.add(jsonDecode(request.body));
          if (pendingRegistration != null) return pendingRegistration!.future;
          if (failRegistration) {
            return http.Response('{"error":{"message":"Sin conexión"}}', 503);
          }
          return http.Response('{}', 200);
        }
        return http.Response('{"items":[],"total":0}', 200);
      }),
    );
    service = NotificationService(
      auth,
      api,
      messaging: messaging,
      localNotifications: local,
    );
  });

  tearDown(() async {
    await service.dispose();
    await messaging.tokens.close();
    api.close();
  });

  Future<void> openHome(WidgetTester tester) async {
    await service.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(auth: auth, api: api, notifications: service),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'verified registration hides activation without claiming delivery',
    (tester) async {
      await openHome(tester);
      expect(service.status.value.phase, NotificationPhase.enabled);
      expect(find.text('Notificaciones activadas'), findsOneWidget);
      expect(find.text('Activar avisos'), findsNothing);
      expect(registrations, 1);
      expect(local.displayed, 0);
      expect(service.target.value, isNull);
      await service.sync();
      await resume(tester);
      expect(registrations, 1);
      expect(messaging.permissionRequests, 0);
      expect(messaging.settingsReads, 3);
      expect(find.text('Activar avisos'), findsNothing);
    },
  );

  testWidgets(
    'permission changes in Android settings update the action on resume',
    (tester) async {
      messaging.permission = AuthorizationStatus.notDetermined;
      await openHome(tester);
      expect(service.status.value.phase, NotificationPhase.permissionRequired);
      expect(find.text('Activar avisos'), findsOneWidget);
      expect(registrations, 0);
      messaging.permission = AuthorizationStatus.authorized;
      await tester.tap(find.text('Activar avisos'));
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones activadas'), findsOneWidget);
      expect(registrations, 1);
      expect(messaging.permissionRequests, 1);

      messaging.permission = AuthorizationStatus.denied;
      await resume(tester);
      expect(service.status.value.phase, NotificationPhase.permissionRequired);
      expect(find.text('Notificaciones activadas'), findsNothing);
      expect(find.text('Activar avisos'), findsOneWidget);
      expect(find.textContaining('habilitalos en Ajustes'), findsOneWidget);
      await tester.tap(find.text('Activar avisos'));
      await tester.pumpAndSettle();
      expect(service.status.value.phase, NotificationPhase.permissionRequired);
      expect(registrations, 1);

      messaging.permission = AuthorizationStatus.authorized;
      await resume(tester);
      expect(service.status.value.phase, NotificationPhase.enabled);
      expect(find.text('Activar avisos'), findsNothing);
      expect(registrations, 1);
      expect(messaging.permissionRequests, 2);
    },
  );

  testWidgets(
    'failed registration offers a retry and only hides it on success',
    (tester) async {
      failRegistration = true;
      await openHome(tester);
      expect(service.status.value.phase, NotificationPhase.error);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Notificaciones activadas'), findsNothing);
      failRegistration = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(registrations, 2);
      expect(service.status.value.phase, NotificationPhase.enabled);
      expect(find.text('Reintentar'), findsNothing);
      await service.sync();
      expect(registrations, 2);
    },
  );

  for (final failure in ['missing token', 'FCM error', 'settings error']) {
    testWidgets('$failure keeps activation retryable', (tester) async {
      messaging.token = failure == 'missing token' ? null : 'fcm-token';
      messaging.failToken = failure == 'FCM error';
      messaging.failSettings = failure == 'settings error';
      await openHome(tester);
      expect(service.status.value.phase, NotificationPhase.error);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(registrations, 0);
      messaging.token = 'fcm-token';
      messaging.failToken = messaging.failSettings = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(service.status.value.phase, NotificationPhase.enabled);
      expect(find.text('Reintentar'), findsNothing);
      expect(registrations, 1);
    });
  }

  testWidgets('initialization failure can be retried from Home', (
    tester,
  ) async {
    local.failInitialize = true;
    await openHome(tester);
    expect(service.status.value.phase, NotificationPhase.error);
    expect(find.text('Reintentar'), findsOneWidget);
    local.failInitialize = false;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(service.status.value.phase, NotificationPhase.enabled);
    expect(find.text('Reintentar'), findsNothing);
    expect(registrations, 1);
    expect(registeredBodies, [
      {'token': 'fcm-token'},
    ]);
  });

  testWidgets('concurrent syncs do not duplicate a pending registration', (
    tester,
  ) async {
    pendingRegistration = Completer<http.Response>();
    await openHome(tester);
    expect(service.status.value.phase, NotificationPhase.checking);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    await Future.wait([service.sync(), service.sync(requestPermission: true)]);
    expect(registrations, 1);
    // Los permisos pueden cambiar mientras se espera la respuesta del servidor.
    messaging.permission = AuthorizationStatus.denied;
    await resume(tester);
    pendingRegistration!.complete(http.Response('{}', 200));
    await tester.pumpAndSettle();
    expect(registrations, 1);
    expect(service.status.value.phase, NotificationPhase.permissionRequired);
    expect(find.text('Activar avisos'), findsOneWidget);
    expect(find.text('Notificaciones activadas'), findsNothing);
  });

  testWidgets(
    'token refresh registers only changed tokens and exposes errors',
    (tester) async {
      await openHome(tester);
      messaging.token = 'new-fcm-token';
      messaging.tokens.add(messaging.token!);
      await tester.pumpAndSettle();
      expect(registrations, 2);
      expect(registeredBodies, [
        {'token': 'fcm-token'},
        {'token': 'new-fcm-token'},
      ]);
      expect(service.status.value.phase, NotificationPhase.enabled);
      messaging.tokens.add(messaging.token!);
      await tester.pumpAndSettle();
      expect(registrations, 2);
      messaging.tokens.addError(Exception('token refresh failed'));
      await tester.pumpAndSettle();
      expect(service.status.value.phase, NotificationPhase.error);
      expect(find.text('Reintentar'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(service.status.value.phase, NotificationPhase.enabled);
      expect(find.text('Reintentar'), findsNothing);
      expect(registrations, 2);
    },
  );

  testWidgets(
    'token rotation during registration is checked after it finishes',
    (tester) async {
      pendingRegistration = Completer<http.Response>();
      await openHome(tester);
      messaging.token = 'rotated-fcm-token';
      messaging.tokens.add(messaging.token!);
      await tester.pump();
      expect(registrations, 1);
      pendingRegistration!.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(registeredBodies, [
        {'token': 'fcm-token'},
        {'token': 'rotated-fcm-token'},
      ]);
      expect(service.status.value.phase, NotificationPhase.enabled);
      await service.sync();
      expect(registrations, 2);
    },
  );

  testWidgets(
    'unlink clears activation and ignores a stale registration result',
    (tester) async {
      pendingRegistration = Completer<http.Response>();
      await openHome(tester);
      await service.unlink();
      pendingRegistration!.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(service.status.value.phase, NotificationPhase.inactive);
      expect(find.text('Activar avisos'), findsOneWidget);
      expect(find.text('Notificaciones activadas'), findsNothing);
    },
  );
}

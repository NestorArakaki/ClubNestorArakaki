import 'dart:async';
import 'dart:convert';

import 'package:club_nestor_arakaki/app.dart';
import 'package:club_nestor_arakaki/models/models.dart';
import 'package:club_nestor_arakaki/screens/auth_screen.dart';
import 'package:club_nestor_arakaki/screens/availability_screen.dart';
import 'package:club_nestor_arakaki/screens/bookings_screen.dart';
import 'package:club_nestor_arakaki/screens/dashboard_screen.dart';
import 'package:club_nestor_arakaki/services/api_client.dart';
import 'package:club_nestor_arakaki/services/auth_service.dart';
import 'package:club_nestor_arakaki/services/notification_service.dart';
import 'package:club_nestor_arakaki/theme.dart';
import 'package:club_nestor_arakaki/widgets/async_view.dart';
import 'package:club_nestor_arakaki/widgets/booking_card.dart';
import 'package:club_nestor_arakaki/widgets/error_panel.dart';
import 'package:club_nestor_arakaki/widgets/venue_card.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;

const venue = <String, dynamic>{
  'id': 1,
  'name': 'Sede Central',
  'address': 'Calle del Club 123',
  'timezone': 'America/Argentina/Buenos_Aires',
};
const court = <String, dynamic>{
  'id': 1,
  'venue_id': 1,
  'name': 'Cancha de tenis',
  'sport': 'tennis',
  'active': true,
};
Json booking(int id, DateTime start, {String status = 'confirmed'}) => {
  'id': id,
  'court_id': 1,
  'starts_at': start.toUtc().toIso8601String(),
  'ends_at': start.add(const Duration(hours: 1)).toUtc().toIso8601String(),
  'status': status,
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class UxAuth extends Fake implements AuthService {
  String? current = 'alice', failureCode;
  int submissions = 0;
  @override
  String? get uid => current;
  @override
  Future<String?> token(bool forceRefresh) async => 'test-token';
  @override
  Future<void> login(String email, String password) async {
    submissions++;
    if (failureCode != null) {
      throw ApiException(
        authMessage(FirebaseAuthException(code: failureCode!)),
      );
    }
  }

  @override
  Future<void> register(String email, String password) =>
      login(email, password);
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late ApiClient api;
  late UxAuth auth;
  late List<Json> rows;
  late bool cancelled;
  late List<String> periods;
  setUp(() {
    auth = UxAuth();
    cancelled = false;
    rows = [];
    periods = [];
    api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: auth.token,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/v1/me':
            return response({'first_name': 'Ana', 'last_name': 'Pérez'});
          case '/api/v1/venues':
            return response({
              'items': [venue],
              'total': 1,
            });
          case '/api/v1/venues/1':
            return response(venue);
          case '/api/v1/venues/1/courts':
            return response({
              'items': [court],
              'total': 1,
            });
          case '/api/v1/venues/1/opening-hours':
            return response([]);
          case '/api/v1/courts/1':
            return response(court);
          case '/api/v1/bookings':
            periods.add(request.url.queryParameters['period']!);
            return response({
              'items': [
                for (final row in rows)
                  {...row, if (cancelled) 'status': 'cancelled'},
              ],
              'total': rows.length,
            });
          case '/api/v1/bookings/42':
            if (request.method == 'DELETE') cancelled = true;
            return response({
              ...rows.firstWhere((row) => row['id'] == 42),
              if (cancelled) 'status': 'cancelled',
            });
          default:
            throw StateError('Unexpected request: ${request.url}');
        }
      }),
    );
  });
  tearDown(() => api.close());

  Future<void> show(WidgetTester tester, Widget child, {Size? size}) async {
    if (size != null) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    }
    await tester.pumpWidget(MaterialApp(theme: clubTheme(), home: child));
    await tester.pumpAndSettle();
  }

  test(
    'reservation phases use status and interval boundaries consistently',
    () {
      final now = DateTime.utc(2030, 1, 1, 12);
      for (final (start, status, phase, upcoming) in [
        (
          now.add(const Duration(hours: 1)),
          'confirmed',
          BookingPhase.upcoming,
          true,
        ),
        (now, 'confirmed', BookingPhase.inProgress, true),
        (
          now.subtract(const Duration(minutes: 30)),
          'confirmed',
          BookingPhase.inProgress,
          true,
        ),
        (
          now.subtract(const Duration(hours: 1)),
          'confirmed',
          BookingPhase.finished,
          false,
        ),
        (
          now.add(const Duration(days: 5)),
          'cancelled',
          BookingPhase.cancelled,
          false,
        ),
        (
          now.subtract(const Duration(days: 5)),
          'cancelled',
          BookingPhase.cancelled,
          false,
        ),
      ]) {
        final row = Booking.fromJson(booking(1, start, status: status));
        expect(row.phaseAt(now), phase);
        expect(row.isUpcomingAt(now), upcoming);
      }
    },
  );

  testWidgets(
    'future cancellations and ended bookings appear only in history',
    (tester) async {
      final now = DateTime.now().toUtc();
      rows = [
        booking(10, now.add(const Duration(days: 1)), status: 'cancelled'),
        booking(11, now.subtract(const Duration(days: 1))),
        booking(12, now.add(const Duration(days: 2))),
        booking(13, now.subtract(const Duration(minutes: 30))),
      ];
      await show(
        tester,
        Scaffold(body: BookingsScreen(api: api)),
        size: const Size(393, 852),
      );
      expect(periods, ['all']);
      expect(find.text('Reserva #10'), findsNothing);
      expect(find.text('Reserva #11'), findsNothing);
      expect(find.text('Reserva #12'), findsOneWidget);
      expect(find.text('Reserva #13'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Confirmada'), findsOneWidget);
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Reserva #10'), findsOneWidget);
      expect(find.text('Reserva #11'), findsOneWidget);
      expect(find.text('Reserva #12'), findsNothing);
      expect(find.text('Reserva #13'), findsNothing);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('Finalizada'), findsOneWidget);
      expect(periods, ['all']);
    },
  );

  test('all reservation pages are preserved before classification', () async {
    final pages = <String>[];
    final now = DateTime.now().toUtc();
    final paginated = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: auth.token,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/bookings')) {
          pages.add(request.url.queryParameters['page']!);
          expect(request.url.queryParameters['period'], 'all');
          expect(request.url.queryParameters['status'], 'all');
          final page = int.parse(pages.last);
          return response({
            'items': [
              booking(
                page,
                now.add(Duration(days: page)),
                status: page == 1 ? 'cancelled' : 'confirmed',
              ),
            ],
            'total': 2,
          });
        }
        if (request.url.path.contains('/courts/')) return response(court);
        return response(venue);
      }),
    );
    addTearDown(paginated.close);
    final result = await paginated.bookingInfo('all');
    expect(pages, ['1', '2']);
    expect(
      result.where((row) => row.booking.isUpcomingAt(now)).single.booking.id,
      2,
    );
    expect(
      result.where((row) => !row.booking.isUpcomingAt(now)).single.booking.id,
      1,
    );
  });

  testWidgets(
    'booking badges provide distinct text, icon and semantic colours',
    (tester) async {
      await show(
        tester,
        const Scaffold(
          body: Column(
            children: [
              BookingStatusBadge(phase: BookingPhase.upcoming),
              BookingStatusBadge(phase: BookingPhase.inProgress),
              BookingStatusBadge(phase: BookingPhase.finished),
              BookingStatusBadge(phase: BookingPhase.cancelled),
            ],
          ),
        ),
      );
      final context = tester.element(find.text('Cancelada'));
      final colors = [
        for (final label in [
          'Confirmada',
          'En curso',
          'Finalizada',
          'Cancelada',
        ])
          tester.widget<Text>(find.text(label)).style!.color,
      ];
      expect(colors.toSet(), hasLength(4));
      expect(colors.last, Theme.of(context).colorScheme.error);
      for (final icon in [
        Icons.check_circle_outline,
        Icons.play_circle_outline,
        Icons.task_alt,
        Icons.cancel_outlined,
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
      }
    },
  );

  testWidgets(
    'cancelling from the list moves the reservation into history on return',
    (tester) async {
      rows = [booking(42, DateTime.now().toUtc().add(const Duration(days: 1)))];
      await show(tester, Scaffold(body: BookingsScreen(api: api)));
      await tester.tap(find.byType(BookingCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar reserva'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelada'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Cancelada')).style!.color,
        Theme.of(tester.element(find.text('Cancelada'))).colorScheme.error,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(BookingCard), findsNothing);
      expect(find.text('No hay reservas en este período.'), findsOneWidget);
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Reserva #42'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
    },
  );

  testWidgets('Home greets the user and opens the next confirmed booking', (
    tester,
  ) async {
    final now = DateTime.now().toUtc();
    rows = [
      booking(1, now.add(const Duration(hours: 2)), status: 'cancelled'),
      booking(42, now.add(const Duration(days: 1))),
    ];
    await show(
      tester,
      HomeScreen(auth: auth, api: api),
      size: const Size(393, 852),
    );
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(find.text('Tu próxima reserva'), findsOneWidget);
    expect(find.text('Reserva #1'), findsNothing);
    expect(find.text('Reserva #42'), findsOneWidget);
    expect(find.text('Sede Central · Cancha de tenis'), findsOneWidget);
    await tester.ensureVisible(find.byType(BookingCard));
    await tester.tap(find.byType(BookingCard));
    await tester.pumpAndSettle();
    expect(find.byType(BookingDetailScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets(
    'empty Home links to real venues and retains all four destinations',
    (tester) async {
      rows = [
        booking(
          10,
          DateTime.now().toUtc().add(const Duration(days: 1)),
          status: 'cancelled',
        ),
      ];
      await show(
        tester,
        HomeScreen(auth: auth, api: api),
        size: const Size(393, 852),
      );
      expect(find.text('Tu próximo partido te espera'), findsOneWidget);
      expect(find.byType(BookingCard), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await tester.ensureVisible(find.text('Explorar sedes'));
      await tester.tap(find.text('Explorar sedes'));
      await tester.pumpAndSettle();
      expect(find.text('Elegí una sede'), findsOneWidget);
      await tester.tap(find.text('Sede Central'));
      await tester.pumpAndSettle();
      expect(find.text('Canchas'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inicio'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(VenueCard));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(VenueCard));
      await tester.pumpAndSettle();
      expect(find.text('Horarios de apertura'), findsOneWidget);
    },
  );

  testWidgets('Home refreshes its next reservation after cancellation', (
    tester,
  ) async {
    rows = [booking(42, DateTime.now().toUtc().add(const Duration(days: 1)))];
    await show(
      tester,
      HomeScreen(auth: auth, api: api),
      size: const Size(393, 852),
    );
    await tester.ensureVisible(find.byType(BookingCard));
    await tester.tap(find.byType(BookingCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar reserva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Tu próximo partido te espera'), findsOneWidget);
    expect(find.byType(BookingCard), findsNothing);
  });

  for (final initial in [false, true]) {
    testWidgets(
      'push opens owned booking with initial target=$initial and refreshes on return',
      (tester) async {
        rows = [
          booking(42, DateTime.now().toUtc().add(const Duration(days: 1))),
        ];
        final service = NotificationService(auth, api);
        addTearDown(service.dispose);
        if (initial) service.target.value = const PushTarget(42, 'alice');
        await show(
          tester,
          HomeScreen(auth: auth, api: api, notifications: service),
        );
        if (!initial) {
          service.target.value = const PushTarget(42, 'other-user');
          await tester.pumpAndSettle();
          expect(find.byType(BookingDetailScreen), findsNothing);
          service.target.value = const PushTarget(42, 'alice');
          await tester.pumpAndSettle();
        }
        expect(find.byType(BookingDetailScreen), findsOneWidget);
        await tester.tap(find.text('Cancelar reserva'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        expect(find.byType(BookingCard), findsNothing);
        await tester.tap(find.text('Historial'));
        await tester.pumpAndSettle();
        expect(find.text('Cancelada'), findsOneWidget);
      },
    );
  }

  for (final network in [true, false]) {
    testWidgets(
      '${network ? 'connection' : 'server'} errors show safe messages and allow a read retry',
      (tester) async {
        var reads = 0;
        await show(
          tester,
          Scaffold(
            body: AsyncView<int>(
              load: () async {
                if (++reads == 1) {
                  throw ApiException(
                    'private traceback',
                    network: network,
                    status: network ? null : 503,
                  );
                }
                return 42;
              },
              builder: (value, _) => Text('Resultado $value'),
            ),
          ),
        );
        expect(
          find.text(
            network
                ? 'No pudimos conectarnos'
                : 'El servidor no está disponible',
          ),
          findsOneWidget,
        );
        expect(
          find.byIcon(
            network ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private traceback'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(reads, 1);
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(reads, 2);
        expect(find.text('Resultado 42'), findsOneWidget);
      },
    );
  }

  testWidgets('read timeout exits loading with a connection error', (
    tester,
  ) async {
    final slow = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: auth.token,
      timeout: const Duration(milliseconds: 100),
      client: MockClient((_) => Completer<http.Response>().future),
    );
    addTearDown(slow.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AsyncView<List<Venue>>(
            load: slow.venues,
            builder: (_, _) => const Text('Cargado'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('No pudimos conectarnos'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test(
    'booking POST is not repeated automatically after an expired session',
    () async {
      var posts = 0;
      final expired = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokenProvider: auth.token,
        client: MockClient((request) async {
          posts++;
          return response({
            'error': {'message': 'Iniciá sesión nuevamente.'},
          }, 401);
        }),
      );
      addTearDown(expired.close);
      await expectLater(
        expired.createBooking(
          1,
          Slot.fromJson({
            'starts_at': '2035-12-20T21:00:00Z',
            'ends_at': '2035-12-20T22:00:00Z',
            'available': true,
          }),
          1,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(posts, 1);
    },
  );

  testWidgets('unexpected exceptions do not expose implementation details', (
    tester,
  ) async {
    await show(
      tester,
      Scaffold(
        body: AsyncView<int>(
          load: () => throw StateError('internal/private.dart stacktrace'),
          builder: (_, _) => const SizedBox(),
        ),
      ),
    );
    expect(find.textContaining('internal/private'), findsNothing);
    expect(find.text('No pudimos cargar la información'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets(
    'login and registration validate empty fields, email and confirmation inline',
    (tester) async {
      await show(tester, AuthScreen(auth: auth), size: const Size(393, 852));
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá un correo válido.'), findsOneWidget);
      expect(find.text('Usá al menos 6 caracteres.'), findsOneWidget);
      expect(auth.submissions, 0);
      await tester.ensureVisible(find.text('Crear una cuenta'));
      await tester.tap(find.text('Crear una cuenta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Registrarme'));
      await tester.tap(find.text('Registrarme'));
      await tester.pumpAndSettle();
      expect(find.text('Repetí tu contraseña.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        'bad',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        '123',
      );
      expect(find.text('Ingresá un correo válido.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        'ana@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        '123456',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Repetir contraseña'),
        '654321',
      );
      await tester.ensureVisible(find.text('Registrarme'));
      await tester.tap(find.text('Registrarme'));
      await tester.pumpAndSettle();
      expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
      expect(auth.submissions, 0);
    },
  );

  for (final (code, register, message) in [
    ('invalid-credential', false, 'Correo o contraseña incorrectos.'),
    ('email-already-in-use', true, 'Ya hay una cuenta con este correo.'),
    ('weak-password', true, 'La contraseña es demasiado débil.'),
    (
      'network-request-failed',
      false,
      'No se pudo conectar con Firebase. Revisá Internet.',
    ),
  ]) {
    testWidgets('Firebase $code is shown beside the form', (tester) async {
      auth.failureCode = code;
      await show(tester, AuthScreen(auth: auth));
      if (register) {
        await tester.tap(find.text('Crear una cuenta'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        'ana@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        '123456',
      );
      if (register) {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Repetir contraseña'),
          '123456',
        );
      }
      await tester.ensureVisible(
        find.text(register ? 'Registrarme' : 'Ingresar'),
      );
      await tester.tap(find.text(register ? 'Registrarme' : 'Ingresar'));
      await tester.pumpAndSettle();
      expect(find.byType(FormErrorMessage), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(auth.submissions, 1);
    });
  }

  testWidgets('phone layout supports larger text in Home and reservations', (
    tester,
  ) async {
    rows = [booking(42, DateTime.now().toUtc().add(const Duration(days: 1)))];
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: clubTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: HomeScreen(auth: auth, api: api),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Mis reservas'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final occupied in [false, true]) {
    testWidgets(
      'availability without free slots is an empty state, occupied=$occupied',
      (tester) async {
        final empty = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          tokenProvider: auth.token,
          client: MockClient(
            (_) async => response({
              'timezone': venue['timezone'],
              'slots': [
                if (occupied)
                  {
                    'starts_at': '2035-12-20T21:00:00Z',
                    'ends_at': '2035-12-20T22:00:00Z',
                    'available': false,
                  },
              ],
            }),
          ),
        );
        addTearDown(empty.close);
        await show(
          tester,
          AvailabilityScreen(
            api: empty,
            venue: Venue.fromJson(venue),
            court: Court.fromJson(court),
          ),
        );
        expect(find.text('No hay horarios disponibles'), findsOneWidget);
        expect(find.byType(ErrorPanel), findsNothing);
        expect(find.text('Confirmar reserva'), findsNothing);
      },
    );
  }
}

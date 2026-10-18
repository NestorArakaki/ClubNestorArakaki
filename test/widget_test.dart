import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:club_nestor_arakaki/app.dart';
import 'package:club_nestor_arakaki/models/models.dart';
import 'package:club_nestor_arakaki/screens/availability_screen.dart';
import 'package:club_nestor_arakaki/screens/bookings_screen.dart';
import 'package:club_nestor_arakaki/services/api_client.dart';
import 'package:club_nestor_arakaki/services/auth_service.dart';

// Dobles exclusivamente de pruebas; la aplicación utiliza FirebaseAuthService.
class TestAuth implements AuthService {
  String? current;
  String? resetEmail;
  final controller = StreamController<String?>.broadcast();
  @override
  String? get uid => current;
  @override
  Stream<String?> get sessions => controller.stream;
  @override
  Future<void> login(String email, String password) async {
    current = 'alice';
    controller.add(current);
  }

  @override
  Future<void> register(String email, String password) =>
      login(email, password);
  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> logout() async {
    current = null;
    controller.add(null);
  }

  @override
  Future<String?> token(bool forceRefresh) async =>
      current == null ? null : 'test-token';
}

final venueJson = <String, dynamic>{
  'id': 1,
  'name': 'Sede Test',
  'address': 'Calle Test',
  'timezone': 'America/Argentina/Buenos_Aires',
};
final courtJson = <String, dynamic>{
  'id': 1,
  'venue_id': 1,
  'name': 'Cancha Test',
  'sport': 'football',
  'active': true,
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> bookingJson([String status = 'confirmed']) => {
  'id': 42,
  'court_id': 1,
  'starts_at': '2035-12-20T21:00:00Z',
  'ends_at': '2035-12-20T23:00:00Z',
  'status': status,
};

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'login validations, recovery, navigation, profile save and logout',
    (tester) async {
      final auth = TestAuth();
      var patched = false;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokenProvider: auth.token,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/venues')) {
            return response({
              'items': [venueJson],
              'total': 1,
            });
          }
          if (request.url.path.endsWith('/bookings')) {
            return response({'items': [], 'total': 0});
          }
          if (request.method == 'PATCH') {
            patched = true;
            expect(jsonDecode(request.body)['first_name'], 'Ana');
          }
          return response({
            'email': 'alice@example.test',
            'first_name': 'Ana',
            'last_name': 'Pérez',
            'birth_date': null,
          });
        }),
      );
      await tester.pumpWidget(ClubApp(auth: auth, api: api));
      auth.controller.add(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresá un correo válido.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Correo electrónico'),
        'alice@example.test',
      );
      await tester.tap(find.text('Recuperar contraseña'));
      await tester.pumpAndSettle();
      expect(auth.resetEmail, 'alice@example.test');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Contraseña'),
        '123456',
      );
      await tester.tap(find.text('Ingresar'));
      await tester.pumpAndSettle();
      expect(find.text('Sede Test'), findsOneWidget);
      await tester.tap(find.text('Mis reservas'));
      await tester.pumpAndSettle();
      expect(find.text('No hay reservas en este período.'), findsOneWidget);
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar perfil'));
      await tester.tap(find.text('Guardar perfil'));
      await tester.pumpAndSettle();
      expect(patched, true);
      await tester.tap(find.byTooltip('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresar'), findsOneWidget);
      expect(find.text('Sede Test'), findsNothing);
      await auth.controller.close();
      api.close();
    },
  );
  testWidgets('registration checks password confirmation', (tester) async {
    final auth = TestAuth();
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: auth.token,
      client: MockClient((_) async => response({'items': [], 'total': 0})),
    );
    await tester.pumpWidget(ClubApp(auth: auth, api: api));
    auth.controller.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'alice@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      '123456',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Repetir contraseña'),
      'different',
    );
    await tester.ensureVisible(find.text('Registrarme'));
    await tester.tap(find.text('Registrarme'));
    await tester.pumpAndSettle();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(auth.uid, isNull);
    await auth.controller.close();
    api.close();
  });
  testWidgets(
    '409 on booking refreshes availability instead of claiming success',
    (tester) async {
      var reads = 0, posts = 0;
      final api = ApiClient(
        baseUrl: 'http://localhost/api/v1',
        tokenProvider: (_) async => 'test',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            posts++;
            return response({
              'error': {'code': 'booking_conflict', 'message': 'Conflicto'},
            }, 409);
          }
          reads++;
          return response({
            'timezone': venueJson['timezone'],
            'slots': [
              {
                'starts_at': '2035-12-20T21:00:00Z',
                'ends_at': '2035-12-20T22:00:00Z',
                'available': reads == 1,
              },
            ],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AvailabilityScreen(
            api: api,
            venue: Venue.fromJson(venueJson),
            court: Court.fromJson(courtJson),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('18:00–19:00'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirmar reserva'));
      await tester.tap(find.text('Confirmar reserva'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(reads, 2);
      expect(find.text('Ocupado o pasado'), findsOneWidget);
      expect(find.textContaining('confirmada.'), findsNothing);
      api.close();
    },
  );
  testWidgets('cancel requires confirmation and refreshes booking details', (
    tester,
  ) async {
    var cancelled = false;
    final api = ApiClient(
      baseUrl: 'http://localhost/api/v1',
      tokenProvider: (_) async => 'test',
      client: MockClient((r) async {
        if (r.method == 'DELETE') cancelled = true;
        if (r.url.path.contains('/bookings/')) {
          return response(bookingJson(cancelled ? 'cancelled' : 'confirmed'));
        }
        if (r.url.path.contains('/courts/')) return response(courtJson);
        return response(venueJson);
      }),
    );
    await tester.pumpWidget(
      MaterialApp(home: BookingDetailScreen(api: api, bookingId: 42)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar reserva'));
    await tester.pumpAndSettle();
    expect(cancelled, false);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(cancelled, true);
    expect(find.text('Estado: Cancelada'), findsOneWidget);
    api.close();
  });
  for (final ambiguous in [false, true]) {
    testWidgets(
      ambiguous
          ? 'lost booking response blocks repeated POST'
          : 'successful booking refreshes occupied slots',
      (tester) async {
        var reads = 0, posts = 0;
        final api = ApiClient(
          baseUrl: 'http://localhost/api/v1',
          tokenProvider: (_) async => 'test',
          client: MockClient((r) async {
            if (r.method == 'POST') {
              posts++;
              if (ambiguous) throw http.ClientException('connection lost');
              return response(bookingJson(), 201);
            }
            reads++;
            return response({
              'timezone': venueJson['timezone'],
              'slots': [
                {
                  'starts_at': '2035-12-20T21:00:00Z',
                  'ends_at': '2035-12-20T22:00:00Z',
                  'available': reads == 1,
                },
              ],
            });
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AvailabilityScreen(
              api: api,
              venue: Venue.fromJson(venueJson),
              court: Court.fromJson(courtJson),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('18:00–19:00'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Confirmar reserva'));
        await tester.tap(find.text('Confirmar reserva'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(reads, 2);
        if (ambiguous) {
          expect(
            find.text(
              'Antes de repetir la operación, verificá si se creó en Mis reservas.',
            ),
            findsOneWidget,
          );
          expect(find.text('Confirmar reserva'), findsNothing);
        } else {
          expect(find.text('Reserva #42 confirmada.'), findsOneWidget);
        }
        api.close();
      },
    );
  }
}

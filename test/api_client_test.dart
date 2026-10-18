import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:club_nestor_arakaki/models/models.dart';
import 'package:club_nestor_arakaki/services/api_client.dart';
import 'package:club_nestor_arakaki/services/formatters.dart';
import 'package:club_nestor_arakaki/services/notification_service.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  ApiClient client(
    Future<http.Response> Function(http.Request) handler, {
    TokenProvider? token,
    Duration? timeout,
  }) => ApiClient(
    baseUrl: 'http://localhost:8000/api/v1/',
    client: MockClient(handler),
    tokenProvider: token ?? (_) async => 'test-id-token',
    timeout: timeout ?? const Duration(seconds: 1),
  );
  http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('base URL must include real versioned contract', () {
    expect(
      () => ApiClient(baseUrl: 'example.com', tokenProvider: (_) async => null),
      throwsA(isA<ApiException>()),
    );
    expect(
      () => ApiClient(
        baseUrl: 'https://example.com',
        tokenProvider: (_) async => null,
      ),
      throwsA(isA<ApiException>()),
    );
  });
  test('venues are public, pagination is complete and UTF8 survives', () async {
    var calls = 0;
    final api = client((request) async {
      expect(request.url.path, '/api/v1/venues');
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.url.queryParameters['page'], '${++calls}');
      return jsonResponse({
        'items': [
          {
            'id': calls,
            'name': 'Sede Fútbol',
            'address': 'Dirección',
            'timezone': 'America/Argentina/Buenos_Aires',
          },
        ],
        'total': 2,
        'page': calls,
        'per_page': 1,
      });
    });
    final rows = await api.venues();
    expect(rows.length, 2);
    expect(rows.first.name, 'Sede Fútbol');
    expect(calls, 2);
  });
  test(
    '401 forces a single token refresh and retries with renewed bearer',
    () async {
      final refreshes = <bool>[];
      var requests = 0;
      final api = client(
        (request) async {
          requests++;
          expect(
            request.headers['Authorization'],
            requests == 1 ? 'Bearer cached' : 'Bearer fresh',
          );
          if (requests == 1) {
            return jsonResponse({
              'error': {'code': 'invalid_token', 'message': 'Expired'},
            }, 401);
          }
          return jsonResponse({
            'id': 1,
            'email': null,
            'first_name': null,
            'last_name': null,
            'birth_date': null,
          });
        },
        token: (force) async {
          refreshes.add(force);
          return force ? 'fresh' : 'cached';
        },
      );
      expect((await api.profile()).firstName, '');
      expect(refreshes, [false, true]);
    },
  );
  test(
    'repeated 401 stops after refresh; null token never sends request',
    () async {
      var calls = 0;
      final api = client((_) async {
        calls++;
        return jsonResponse({
          'error': {'message': 'Invalid'},
        }, 401);
      });
      await expectLater(
        api.profile(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(calls, 2);
      final missing = client((_) async {
        fail('must not send');
      }, token: (_) async => null);
      await expectLater(missing.profile(), throwsA(isA<ApiException>()));
    },
  );
  for (final status in [400, 404, 409, 422, 500, 503]) {
    test(
      'HTTP $status preserves structured error and never retries mutation',
      () async {
        var calls = 0;
        final api = client((_) async {
          calls++;
          return jsonResponse({
            'error': {'code': 'server_code', 'message': 'Mensaje claro'},
          }, status);
        });
        await expectLater(
          api.cancel(42),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', status)
                .having((e) => e.code, 'code', 'server_code')
                .having((e) => e.message, 'message', 'Mensaje claro')
                .having((e) => e.network, 'network', false),
          ),
        );
        expect(calls, 1);
      },
    );
  }
  test(
    'network and timeout are distinct from HTTP; POST never silently repeats',
    () async {
      var calls = 0;
      final api = client((_) async {
        calls++;
        throw http.ClientException('offline');
      });
      await expectLater(
        api.request('POST', '/bookings', authenticated: true, body: {}),
        throwsA(isA<ApiException>().having((e) => e.network, 'network', true)),
      );
      expect(calls, 1);
      final slow = client(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        slow.venues(),
        throwsA(isA<ApiException>().having((e) => e.network, 'network', true)),
      );
    },
  );
  test('non JSON responses have a recoverable message', () async {
    final api = client(
      (_) async => http.Response('<html>Starting</html>', 503),
    );
    await expectLater(
      api.venues(),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 503)),
    );
  });
  test(
    'booking body uses slot UTC instant, integer duration and no owner',
    () async {
      final slot = Slot.fromJson({
        'starts_at': '2030-12-20T18:00:00-03:00',
        'ends_at': '2030-12-20T19:00:00-03:00',
        'available': true,
      });
      final api = client((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/bookings');
        expect(jsonDecode(request.body), {
          'court_id': 1,
          'starts_at': '2030-12-20T21:00:00.000Z',
          'duration_hours': 2,
        });
        return jsonResponse({
          'id': 42,
          'court_id': 1,
          'starts_at': '2030-12-20T21:00:00Z',
          'ends_at': '2030-12-20T23:00:00Z',
          'status': 'confirmed',
        }, 201);
      });
      final booking = await api.createBooking(1, slot, 2);
      expect(booking.canCancel, true);
      expect(booking.endsAt.difference(booking.startsAt).inHours, 2);
    },
  );
  test(
    'availability only offers contiguous free hours and uses venue timezone',
    () {
      final a = Availability.fromJson({
        'timezone': 'America/Argentina/Buenos_Aires',
        'slots': [
          {
            'starts_at': '2030-12-20T21:00:00Z',
            'ends_at': '2030-12-20T22:00:00Z',
            'available': true,
          },
          {
            'starts_at': '2030-12-20T22:00:00Z',
            'ends_at': '2030-12-20T23:00:00Z',
            'available': true,
          },
          {
            'starts_at': '2030-12-20T23:00:00Z',
            'ends_at': '2030-12-21T00:00:00Z',
            'available': false,
          },
        ],
      });
      expect(a.maxDuration(0), 2);
      expect(a.maxDuration(1), 1);
      expect(a.maxDuration(2), 0);
      expect(hour(a.slots.first.startsAt, a.timezone), '18:00');
    },
  );
  test(
    'profile patch never includes read-only fields; device DELETE has JSON',
    () async {
      var calls = 0;
      final api = client((r) async {
        calls++;
        if (r.method == 'PATCH') {
          expect(jsonDecode(r.body), {
            'first_name': 'Ana',
            'last_name': 'Pérez',
            'birth_date': null,
          });
          return jsonResponse({
            'email': 'signed@example.test',
            'first_name': 'Ana',
            'last_name': 'Pérez',
            'birth_date': null,
          });
        }
        expect(r.url.path, '/api/v1/devices');
        expect(jsonDecode(r.body), {'token': 'registration-test-token'});
        return jsonResponse({'registered': r.method == 'POST'});
      });
      expect(
        (await api.updateProfile({
          'first_name': 'Ana',
          'last_name': 'Pérez',
          'birth_date': null,
        })).email,
        'signed@example.test',
      );
      await api.registerDevice('registration-test-token');
      await api.unregisterDevice('registration-test-token');
      expect(calls, 3);
    },
  );
  test(
    'form validation rejects blank names, invalid email, short password and normalized bad dates',
    () {
      expect(requiredName('  '), isNotNull);
      expect(requiredName('Ana'), isNull);
      expect(emailValidator('bad'), isNotNull);
      expect(emailValidator('ana@example.com'), isNull);
      expect(passwordValidator('12345'), isNotNull);
      expect(passwordValidator('123456'), isNull);
      expect(birthValidator('2001-02-29'), isNotNull);
      expect(birthValidator('2000-02-29'), isNull);
      expect(birthValidator('1899-01-01'), isNotNull);
      expect(birthValidator('2999-01-01'), isNotNull);
      expect(birthValidator(''), isNull);
    },
  );
  test('notification targets validate event and booking id', () {
    expect(
      PushTarget.parse({
        'type': 'unknown',
        'booking_id': '1',
        'recipient_uid': 'alice',
      }),
      isNull,
    );
    expect(
      PushTarget.parse({
        'type': 'booking_created',
        'booking_id': '-1',
        'recipient_uid': 'alice',
      }),
      isNull,
    );
    expect(
      PushTarget.parse({
        'type': 'booking_cancelled',
        'booking_id': '42',
        'recipient_uid': 'alice',
      })!.bookingId,
      42,
    );
  });
  test(
    'catalog, opening hours, availability and booking joins use documented paths',
    () async {
      final paths = <String>[];
      final api = client((r) async {
        paths.add(r.url.path);
        switch (r.url.path) {
          case '/api/v1/venues/1/courts':
            return jsonResponse({
              'items': [
                {
                  'id': 3,
                  'venue_id': 1,
                  'name': 'Tenis',
                  'sport': 'tennis',
                  'active': true,
                },
              ],
              'total': 1,
            });
          case '/api/v1/venues/1/opening-hours':
            return jsonResponse([
              {'weekday': 0, 'open_hour': 8, 'close_hour': 24},
            ]);
          case '/api/v1/courts/3/availability':
            expect(r.url.queryParameters['date'], '2035-12-20');
            return jsonResponse({
              'timezone': 'America/Argentina/Buenos_Aires',
              'slots': [],
            });
          case '/api/v1/bookings':
            expect(r.url.queryParameters['period'], 'past');
            return jsonResponse({
              'items': [
                {
                  'id': 42,
                  'court_id': 3,
                  'starts_at': '2020-12-20T12:00:00Z',
                  'ends_at': '2020-12-20T13:00:00Z',
                  'status': 'confirmed',
                },
              ],
              'total': 1,
            });
          case '/api/v1/courts/3':
            return jsonResponse({
              'id': 3,
              'venue_id': 1,
              'name': 'Tenis',
              'sport': 'tennis',
              'active': false,
            });
          case '/api/v1/venues/1':
            return jsonResponse({
              'id': 1,
              'name': 'Sede Test',
              'address': 'Calle Test',
              'timezone': 'America/Argentina/Buenos_Aires',
            });
          default:
            fail('Unexpected contract path');
        }
      });
      expect((await api.courts(1)).first.name, 'Tenis');
      expect((await api.hours(1)).first.close, 24);
      expect((await api.availability(3, '2035-12-20')).slots, isEmpty);
      final info = (await api.bookingInfo('past')).single;
      expect(info.court.active, false);
      expect(info.venue.name, 'Sede Test');
      expect(info.booking.canCancel, false);
      expect(paths.length, 6);
    },
  );
}

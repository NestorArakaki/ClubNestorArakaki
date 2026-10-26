import 'dart:convert';

import 'package:club_nestor_arakaki/models/models.dart';
import 'package:club_nestor_arakaki/screens/availability_screen.dart';
import 'package:club_nestor_arakaki/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:timezone/data/latest.dart' as tz;

Json slot(int utcHour, {bool available = true, int year = 2035}) => {
  'starts_at': DateTime.utc(year, 12, 20, utcHour).toIso8601String(),
  'ends_at': DateTime.utc(year, 12, 20, utcHour + 1).toIso8601String(),
  'available': available,
};

Future<void> openScreen(
  WidgetTester tester,
  List<Json> slots, {
  Future<http.Response> Function(http.Request)? post,
  VoidCallback? onRead,
}) async {
  final api = ApiClient(
    baseUrl: 'http://localhost/api/v1',
    tokenProvider: (_) async => 'test-token',
    client: MockClient((request) async {
      if (request.method == 'POST') {
        return post!(request);
      }
      onRead?.call();
      return http.Response(
        jsonEncode({
          'timezone': 'America/Argentina/Buenos_Aires',
          'slots': slots,
        }),
        200,
      );
    }),
  );
  addTearDown(api.close);
  await tester.pumpWidget(
    MaterialApp(
      home: AvailabilityScreen(
        api: api,
        venue: Venue.fromJson({
          'id': 1,
          'name': 'Sede Test',
          'address': 'Calle Test',
          'timezone': 'America/Argentina/Buenos_Aires',
        }),
        court: Court.fromJson({
          'id': 1,
          'venue_id': 1,
          'name': 'Cancha Test',
          'sport': 'football',
          'active': true,
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> toggle(WidgetTester tester, int index) async {
  final finder = find.byKey(ValueKey('slot-$index'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<bool?> checks(WidgetTester tester) => tester
    .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
    .map((tile) => tile.value)
    .toList();

Future<void> openConfirmation(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Confirmar reserva'));
  await tester.tap(find.text('Confirmar reserva'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(tz.initializeTimeZones);

  testWidgets(
    'checks a contiguous range in both directions and sends its start and duration',
    (tester) async {
      var posts = 0;
      await openScreen(
        tester,
        [slot(21), slot(22), slot(23)],
        post: (request) async {
          posts++;
          expect(jsonDecode(request.body), {
            'court_id': 1,
            'starts_at': '2035-12-20T21:00:00.000Z',
            'duration_hours': 3,
          });
          return http.Response(
            jsonEncode({
              'id': 42,
              'court_id': 1,
              'starts_at': '2035-12-20T21:00:00Z',
              'ends_at': '2035-12-21T00:00:00Z',
              'status': 'confirmed',
            }),
            201,
          );
        },
      );
      await toggle(tester, 1);
      await toggle(tester, 2);
      await toggle(tester, 0);
      expect(checks(tester), [true, true, true]);
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
      expect(
        find.text('20/12/2035 18:00 – 20/12/2035 21:00\nDuración: 3 hora(s)'),
        findsOneWidget,
      );
      await openConfirmation(tester);
      expect(posts, 0);
      expect(find.textContaining('Duración: 3 hora(s)'), findsNWidgets(2));
      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(checks(tester), [true, true, true]);
      await openConfirmation(tester);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(checks(tester), [false, false, false]);
      expect(find.text('Reserva #42 confirmada.'), findsOneWidget);
    },
  );

  testWidgets(
    'unchecking edges and an interior block never leaves a disconnected range',
    (tester) async {
      await openScreen(tester, [
        for (var hour = 21; hour < 26; hour++) slot(hour),
      ]);
      for (final index in [1, 2, 3, 4]) {
        await toggle(tester, index);
      }
      expect(checks(tester), [false, true, true, true, true]);
      await toggle(tester, 2);
      expect(checks(tester), [false, true, false, false, false]);
      await toggle(tester, 2);
      await toggle(tester, 3);
      await toggle(tester, 1);
      expect(checks(tester), [false, false, true, true, false]);
      await toggle(tester, 3);
      expect(checks(tester), [false, false, true, false, false]);
      await toggle(tester, 2);
      expect(checks(tester), [false, false, false, false, false]);
      expect(find.text('Confirmar reserva'), findsNothing);
    },
  );

  testWidgets('rejects a separate free block until its neighbour is selected', (
    tester,
  ) async {
    await openScreen(tester, [slot(21), slot(22), slot(23)]);
    await toggle(tester, 0);
    await toggle(tester, 2);
    expect(checks(tester), [true, false, false]);
    expect(
      find.text('Elegí un bloque disponible contiguo a la selección.'),
      findsOneWidget,
    );
    await toggle(tester, 1);
    await toggle(tester, 2);
    expect(checks(tester), [true, true, true]);
  });

  testWidgets('occupied and past blocks are disabled and cannot be crossed', (
    tester,
  ) async {
    await openScreen(tester, [
      slot(21, year: 2000),
      slot(21),
      slot(22, available: false),
      slot(23),
    ]);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('slot-0')))
          .onChanged,
      isNull,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('slot-2')))
          .onChanged,
      isNull,
    );
    await toggle(tester, 1);
    await toggle(tester, 3);
    expect(checks(tester), [false, true, false, false]);
  });

  testWidgets(
    'adjacent list entries with a time gap cannot form a reservation',
    (tester) async {
      await openScreen(tester, [slot(21), slot(23)]);
      await toggle(tester, 0);
      await toggle(tester, 1);
      expect(checks(tester), [true, false]);
    },
  );

  testWidgets('refresh clears every selected block', (tester) async {
    var reads = 0;
    await openScreen(
      tester,
      [slot(21), slot(22)],
      onRead: () {
        reads++;
      },
    );
    await toggle(tester, 0);
    await toggle(tester, 1);
    expect(checks(tester), [true, true]);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(checks(tester), [false, false]);
    expect(find.text('Confirmar reserva'), findsNothing);
  });
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

typedef TokenProvider = Future<String?> Function(bool forceRefresh);

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.status,
    this.code,
    this.network = false,
  });
  final String message;
  final int? status;
  final String? code;
  final bool network;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.tokenProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
  }) : base = Uri.parse(baseUrl.replaceFirst(RegExp(r'/+$'), '')),
       _client = client ?? http.Client() {
    if (!['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        !base.path.endsWith('/api/v1') ||
        base.hasQuery ||
        base.hasFragment ||
        base.userInfo.isNotEmpty) {
      throw const ApiException(
        'API_BASE_URL debe ser http(s)://servidor/api/v1.',
      );
    }
    if (const bool.fromEnvironment('dart.vm.product') &&
        base.scheme != 'https') {
      throw const ApiException(
        'La versión de producción requiere una API HTTPS.',
      );
    }
  }
  final Uri base;
  final TokenProvider tokenProvider;
  final http.Client _client;
  final Duration timeout;
  void close() => _client.close();

  Future<dynamic> request(
    String method,
    String path, {
    bool authenticated = false,
    Json? body,
    Map<String, String>? query,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final headers = <String, String>{'Accept': 'application/json'};
      if (body != null) headers['Content-Type'] = 'application/json';
      if (authenticated) {
        final token = await tokenProvider(attempt == 1);
        if (token == null || token.isEmpty) {
          throw const ApiException('Iniciá sesión nuevamente.', status: 401);
        }
        headers['Authorization'] = 'Bearer $token';
      }
      final uri = base.replace(
        path: '${base.path}$path',
        queryParameters: query,
      );
      late http.Response response;
      try {
        final req = http.Request(method, uri)..headers.addAll(headers);
        if (body != null) req.body = jsonEncode(body);
        response = await (() async => http.Response.fromStream(
          await _client.send(req),
        ))().timeout(timeout);
      } on TimeoutException {
        throw const ApiException(
          'La conexión tardó demasiado. Render puede estar iniciando. Reintentá en un momento.',
          network: true,
        );
      } on http.ClientException {
        throw const ApiException(
          'No se pudo conectar. Revisá Internet y la dirección de la API.',
          network: true,
        );
      }
      if (response.statusCode == 401 && authenticated && attempt == 0) continue;
      dynamic decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw ApiException(
          'El servidor respondió sin JSON válido. Puede estar iniciando; reintentá.',
          status: response.statusCode,
          code: 'invalid_response',
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final error = decoded is Map ? decoded['error'] : null;
      final messages = <int, String>{
        400: 'La solicitud contiene datos inválidos.',
        401: 'Tu sesión no es válida. Cerrá sesión e ingresá nuevamente.',
        404: 'El recurso solicitado ya no está disponible.',
        409: 'El horario cambió o la reserva ya comenzó. Actualizá los datos.',
        422: 'Revisá la fecha, el horario y los campos ingresados.',
        500: 'Ocurrió un error en el servidor. Reintentá más tarde.',
        503: 'El servicio no está disponible. Reintentá en un momento.',
      };
      throw ApiException(
        error is Map && error['message'] is String
            ? error['message'] as String
            : messages[response.statusCode] ??
                  'No se pudo completar la operación.',
        status: response.statusCode,
        code: error is Map ? error['code'] as String? : null,
      );
    }
    throw const ApiException('Iniciá sesión nuevamente.', status: 401);
  }

  Future<List<T>> _all<T>(
    String path,
    T Function(Json) parse, {
    bool authenticated = false,
    Map<String, String> query = const {},
  }) async {
    final items = <T>[];
    for (var page = 1; ; page++) {
      final json =
          await request(
                'GET',
                path,
                authenticated: authenticated,
                query: {...query, 'page': '$page', 'per_page': '100'},
              )
              as Json;
      final batch = json['items'] as List;
      items.addAll(batch.map((e) => parse(e as Json)));
      if (batch.isEmpty || items.length >= (json['total'] as int)) return items;
    }
  }

  Future<List<Venue>> venues() => _all('/venues', Venue.fromJson);
  Future<Venue> venue(int id) async =>
      Venue.fromJson(await request('GET', '/venues/$id') as Json);
  Future<List<Court>> courts(int venueId) =>
      _all('/venues/$venueId/courts', Court.fromJson);
  Future<Court> court(int id) async =>
      Court.fromJson(await request('GET', '/courts/$id') as Json);
  Future<List<OpeningHour>> hours(int venueId) async =>
      (await request('GET', '/venues/$venueId/opening-hours') as List)
          .map((e) => OpeningHour.fromJson(e as Json))
          .toList();
  Future<Availability> availability(int courtId, String date) async =>
      Availability.fromJson(
        await request(
              'GET',
              '/courts/$courtId/availability',
              query: {'date': date},
            )
            as Json,
      );
  Future<Booking> createBooking(int courtId, Slot slot, int duration) async =>
      Booking.fromJson(
        await request(
              'POST',
              '/bookings',
              authenticated: true,
              body: {
                'court_id': courtId,
                'starts_at': slot.startsAt.toUtc().toIso8601String(),
                'duration_hours': duration,
              },
            )
            as Json,
      );
  Future<List<Booking>> bookings(String period) => _all(
    '/bookings',
    Booking.fromJson,
    authenticated: true,
    query: {'period': period, 'status': 'all'},
  );
  Future<Booking> booking(int id) async => Booking.fromJson(
    await request('GET', '/bookings/$id', authenticated: true) as Json,
  );
  Future<Booking> cancel(int id) async => Booking.fromJson(
    await request('DELETE', '/bookings/$id', authenticated: true) as Json,
  );
  Future<Profile> profile() async => Profile.fromJson(
    await request('GET', '/me', authenticated: true) as Json,
  );
  Future<Profile> updateProfile(Json fields) async => Profile.fromJson(
    await request('PATCH', '/me', authenticated: true, body: fields) as Json,
  );
  Future<void> registerDevice(String token) async {
    await request(
      'POST',
      '/devices',
      authenticated: true,
      body: {'token': token},
    );
  }

  Future<void> unregisterDevice(String token) async {
    await request(
      'DELETE',
      '/devices',
      authenticated: true,
      body: {'token': token},
    );
  }

  Future<List<BookingInfo>> bookingInfo(String period) async {
    final rows = await bookings(period);
    final courtsById = <int, Court>{};
    final venuesById = <int, Venue>{};
    final result = <BookingInfo>[];
    for (final row in rows) {
      final c = courtsById[row.courtId] ??= await court(row.courtId);
      final v = venuesById[c.venueId] ??= await venue(c.venueId);
      result.add(BookingInfo(row, c, v));
    }
    return result;
  }
}

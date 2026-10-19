import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

String dateOnly(DateTime day) => DateFormat('yyyy-MM-dd').format(day);
DateTime venueNow(String zone) => tz.TZDateTime.now(tz.getLocation(zone));
String venueTime(DateTime instant, String zone) =>
    DateFormat('dd/MM/yyyy HH:mm')
        .format(tz.TZDateTime.from(instant, tz.getLocation(zone)));
String hour(DateTime instant, String zone) =>
    DateFormat('HH:mm')
        .format(tz.TZDateTime.from(instant, tz.getLocation(zone)));

String? requiredName(String? value) {
  if (value == null || value.trim().isEmpty) return 'Completá este campo.';
  if (value.length > 100) return 'Máximo 100 caracteres.';
  return null;
}

String? emailValidator(String? value) =>
    value != null &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? null
    : 'Ingresá un correo válido.';
String? passwordValidator(String? value) =>
    value != null && value.length >= 6 ? null : 'Usá al menos 6 caracteres.';
String? birthValidator(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      dateOnly(parsed) != value ||
      parsed.isBefore(DateTime(1900)) ||
      parsed.isAfter(DateTime.now())) {
    return 'Usá una fecha válida entre 1900 y hoy (AAAA-MM-DD).';
  }
  return null;
}

String sportLabel(String sport) => switch (sport) {
  'football' => 'Fútbol',
  'tennis' => 'Tenis',
  'padel' => 'Paddle',
  'basketball' => 'Básquet',
  'multipurpose' => 'Multideporte',
  _ => sport,
};

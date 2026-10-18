import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({
    super.key,
    required this.api,
    required this.venue,
    required this.court,
  });
  final ApiClient api;
  final Venue venue;
  final Court court;
  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  late DateTime _day;
  int? _selected;
  int _duration = 1, _revision = 0;
  bool _busy = false, _uncertain = false;
  @override
  void initState() {
    super.initState();
    final today = venueNow(widget.venue.timezone);
    _day = DateTime(today.year, today.month, today.day);
  }

  void _reload() {
    setState(() {
      _selected = null;
      _duration = 1;
      _revision++;
    });
  }

  Future<void> _chooseDay() async {
    final now = venueNow(widget.venue.timezone);
    final today = DateTime(now.year, now.month, now.day);
    final chosen = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: DateTime(today.year + 2, today.month, today.day),
    );
    if (chosen != null && mounted) {
      setState(() {
        _day = chosen;
        _selected = null;
        _duration = 1;
        _revision++;
      });
    }
  }

  Future<void> _book(Availability data) async {
    if (_selected == null || _busy) return;
    final slot = data.slots[_selected!];
    if (!await confirm(
      context,
      'Confirmar reserva',
      '${widget.venue.name}\n${widget.court.name}\n${venueTime(slot.startsAt, data.timezone)}\nDuración: $_duration hora(s)\nZona: ${data.timezone}',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      final result = await widget.api.createBooking(
        widget.court.id,
        slot,
        _duration,
      );
      if (mounted) {
        showMessage(context, 'Reserva #${result.id} confirmada.');
        _reload();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.network ||
          e.code == 'invalid_response' ||
          (e.status != null && e.status! >= 500)) {
        // El POST puede haberse confirmado aunque no hayamos recibido respuesta.
        setState(() {
          _uncertain = true;
        });
        showMessage(
          context,
          'No pudimos confirmar el resultado. Revisá Mis reservas antes de intentar otra vez.',
        );
      } else {
        showMessage(
          context,
          e.status == 409
              ? 'El turno ya no está disponible. Actualizamos los horarios.'
              : e.message,
        );
      }
      _reload();
    } catch (_) {
      if (mounted) {
        setState(() {
          _uncertain = true;
        });
        showMessage(
          context,
          'Resultado desconocido. Revisá Mis reservas antes de volver a reservar.',
        );
        _reload();
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.court.name)),
    body: Column(
      children: [
        ListTile(
          title: Text('${widget.venue.name} · ${widget.court.sport}'),
          subtitle: Text('Fecha: ${dateOnly(_day)} · ${widget.venue.timezone}'),
          trailing: IconButton(
            tooltip: 'Elegir fecha',
            onPressed: _busy ? null : _chooseDay,
            icon: const Icon(Icons.calendar_month),
          ),
        ),
        if (_uncertain)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  'Antes de repetir la operación, verificá si se creó en Mis reservas.',
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (route) => route.isFirst),
                  child: const Text('Volver al inicio'),
                ),
              ],
            ),
          ),
        Expanded(
          child: AsyncView<Availability>(
            key: ValueKey('${dateOnly(_day)}-$_revision'),
            load: () =>
                widget.api.availability(widget.court.id, dateOnly(_day)),
            builder: (data, refresh) => RefreshIndicator(
              onRefresh: () async {
                _reload();
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Horarios de la sede. Los turnos ocupados o pasados están deshabilitados.',
                  ),
                  if (data.slots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'La sede está cerrada o la cancha no tiene turnos para esta fecha.',
                      ),
                    ),
                  for (var i = 0; i < data.slots.length; i++)
                    ListTile(
                      selected: _selected == i,
                      enabled: data.slots[i].available && !_busy && !_uncertain,
                      leading: Icon(
                        _selected == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(
                        '${hour(data.slots[i].startsAt, data.timezone)}–${hour(data.slots[i].endsAt, data.timezone)}',
                      ),
                      subtitle: Text(
                        data.slots[i].available
                            ? 'Disponible'
                            : 'Ocupado o pasado',
                      ),
                      onTap: () => setState(() {
                        _selected = i;
                        _duration = 1;
                      }),
                    ),
                  if (_selected != null) ...[
                    DropdownButtonFormField<int>(
                      key: ValueKey('$_selected-$_duration'),
                      initialValue: _duration,
                      decoration: const InputDecoration(labelText: 'Duración'),
                      items: [
                        for (var n = 1; n <= data.maxDuration(_selected!); n++)
                          DropdownMenuItem(value: n, child: Text('$n hora(s)')),
                      ],
                      onChanged: _busy || _uncertain
                          ? null
                          : (value) => setState(() {
                              _duration = value!;
                            }),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy || _uncertain ? null : () => _book(data),
                      child: Text(_busy ? 'Reservando…' : 'Confirmar reserva'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

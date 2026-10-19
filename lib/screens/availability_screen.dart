import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';
import '../widgets/empty_state.dart';

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
  int? _first, _last;
  int _revision = 0;
  bool _busy = false, _uncertain = false;

  int get _duration => _first == null ? 0 : _last! - _first! + 1;

  bool _isSelected(int index) =>
      _first != null && index >= _first! && index <= _last!;

  bool _isAvailable(Slot slot) =>
      slot.available && slot.startsAt.isAfter(DateTime.now());

  void _toggleSlot(Availability data, int index) {
    if (_busy || _uncertain || !_isAvailable(data.slots[index])) return;
    if (_first == null) {
      setState(() {
        _first = _last = index;
      });
      return;
    }
    if (_isSelected(index)) {
      setState(() {
        if (_first == _last) {
          _first = _last = null;
        } else if (index == _first) {
          _first = index + 1;
        } else {
          // Quitar un bloque intermedio también quita los posteriores.
          _last = index - 1;
        }
      });
      return;
    }
    final first = index < _first! ? index : _first!;
    final last = index > _last! ? index : _last!;
    if ((index != _first! - 1 && index != _last! + 1) ||
        last - first + 1 > data.maxDuration(first)) {
      showMessage(
        context,
        'Elegí un bloque disponible contiguo a la selección.',
      );
      return;
    }
    setState(() {
      _first = first;
      _last = last;
    });
  }

  String _selectionSummary(Availability data) =>
      '${venueTime(data.slots[_first!].startsAt, data.timezone)} – '
      '${venueTime(data.slots[_last!].endsAt, data.timezone)}\n'
      'Duración: $_duration hora(s)';
  @override
  void initState() {
    super.initState();
    final today = venueNow(widget.venue.timezone);
    _day = DateTime(today.year, today.month, today.day);
  }

  void _reload() {
    setState(() {
      _first = _last = null;
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
        _first = _last = null;
        _revision++;
      });
    }
  }

  Future<void> _book(Availability data) async {
    if (_first == null || _busy || _uncertain) return;
    if (!data.slots.sublist(_first!, _last! + 1).every(_isAvailable)) {
      showMessage(
        context,
        'Un horario seleccionado ya pasó. Actualizamos los turnos.',
      );
      _reload();
      return;
    }
    final slot = data.slots[_first!];
    final duration = _duration;
    if (!await confirm(
      context,
      'Confirmar reserva',
      '${widget.venue.name}\n${widget.court.name}\n${_selectionSummary(data)}\nZona: ${data.timezone}',
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
        duration,
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
                    const EmptyState(
                      icon: Icons.event_busy,
                      title: 'No hay horarios disponibles',
                      message: 'La sede está cerrada o la cancha no tiene turnos para esta fecha. Probá con otra fecha.',
                    ),
                  if (data.slots.isNotEmpty && !data.slots.any(_isAvailable))
                    const EmptyState(
                      icon: Icons.event_busy,
                      title: 'No hay horarios disponibles',
                      message: 'Los turnos de esta fecha están ocupados o ya pasaron. Probá con otra fecha.',
                    ),
                  const Text(
                    'Marcá bloques consecutivos. Al desmarcar uno intermedio, '
                    'también se desmarcan los posteriores.',
                  ),
                  for (var i = 0; i < data.slots.length; i++)
                    CheckboxListTile(
                      key: ValueKey('slot-$i'),
                      value: _isSelected(i),
                      selected: _isSelected(i),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        '${hour(data.slots[i].startsAt, data.timezone)}–${hour(data.slots[i].endsAt, data.timezone)}',
                      ),
                      subtitle: Text(
                        _isAvailable(data.slots[i])
                            ? 'Disponible'
                            : 'Ocupado o pasado',
                      ),
                      onChanged:
                          !_isAvailable(data.slots[i]) || _busy || _uncertain
                          ? null
                          : (_) => _toggleSlot(data, i),
                    ),
                  if (_first != null) ...[
                    Text(
                      _selectionSummary(data),
                      style: Theme.of(context).textTheme.titleMedium,
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

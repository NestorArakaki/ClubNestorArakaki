import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';
import '../widgets/booking_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_panel.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, required this.api});
  final ApiClient api;
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String _period = 'future';
  int _revision = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'future', label: Text('Próximas / en curso')),
            ButtonSegment(value: 'past', label: Text('Historial')),
          ],
          selected: {_period},
          onSelectionChanged: (values) => setState(() {
            _period = values.first;
          }),
        ),
      ),
      Expanded(
        child: AsyncView<List<BookingInfo>>(
          key: ValueKey(_revision),
          load: () => widget.api.bookingInfo('all'),
          builder: (allRows, refresh) {
            final now = DateTime.now();
            final rows =
                allRows
                    .where(
                      (row) =>
                          row.booking.isUpcomingAt(now) ==
                          (_period == 'future'),
                    )
                    .toList()
                  ..sort(
                    (a, b) => _period == 'future'
                        ? a.booking.startsAt.compareTo(b.booking.startsAt)
                        : b.booking.endsAt.compareTo(a.booking.endsAt),
                  );
            return RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (rows.isEmpty)
                    EmptyState(
                      icon: _period == 'future'
                          ? Icons.event_available
                          : Icons.history,
                      title: 'No hay reservas en este período.',
                      message: _period == 'future'
                          ? 'Tus próximos turnos aparecerán acá cuando reserves una cancha.'
                          : 'Acá verás tus reservas finalizadas y canceladas.',
                    ),
                  for (final row in rows)
                    BookingCard(
                      row: row,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => BookingDetailScreen(
                              api: widget.api,
                              bookingId: row.booking.id,
                            ),
                          ),
                        );
                        if (mounted) {
                          setState(() {
                            _revision++;
                          });
                        }
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ],
  );
}

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.api,
    required this.bookingId,
  });
  final ApiClient api;
  final int bookingId;
  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _busy = false;
  Future<BookingInfo> _load() async {
    final booking = await widget.api.booking(widget.bookingId);
    final court = await widget.api.court(booking.courtId);
    return BookingInfo(booking, court, await widget.api.venue(court.venueId));
  }

  Future<void> _cancel(Future<void> Function() refresh) async {
    if (!await confirm(
      context,
      'Cancelar reserva',
      'Se liberará el horario de tu reserva #${widget.bookingId}.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
    });
    try {
      await widget.api.cancel(widget.bookingId);
      if (mounted) showMessage(context, 'Reserva cancelada.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyErrorMessage(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
        await refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Reserva #${widget.bookingId}')),
    body: AsyncView<BookingInfo>(
      load: _load,
      builder: (row, refresh) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              row.venue.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(row.venue.address),
            Text('${row.court.name} · ${sportLabel(row.court.sport)}'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: BookingStatusBadge(
                phase: row.booking.phaseAt(DateTime.now()),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Inicio: ${venueTime(row.booking.startsAt, row.venue.timezone)}',
            ),
            Text('Fin: ${venueTime(row.booking.endsAt, row.venue.timezone)}'),
            Text('Zona: ${row.venue.timezone}'),
            const SizedBox(height: 24),
            if (row.booking.canCancel)
              FilledButton(
                onPressed: _busy ? null : () => _cancel(refresh),
                child: Text(_busy ? 'Cancelando…' : 'Cancelar reserva'),
              ),
            if (!row.booking.canCancel && row.booking.status == 'confirmed')
              const Text('La reserva finalizó y no se puede cancelar.'),
          ],
        ),
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/formatters.dart';
import '../widgets/async_view.dart';

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
          key: ValueKey('$_period-$_revision'),
          load: () => widget.api.bookingInfo(_period),
          builder: (rows, refresh) => RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No hay reservas en este período.'),
                  ),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text('${row.venue.name} · ${row.court.name}'),
                      subtitle: Text(
                        '${venueTime(row.booking.startsAt, row.venue.timezone)}\nHasta ${venueTime(row.booking.endsAt, row.venue.timezone)}\n${row.booking.status == 'cancelled' ? 'Cancelada' : 'Confirmada'} · #${row.booking.id}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
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
                  ),
              ],
            ),
          ),
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
      if (mounted) showMessage(context, '$e');
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
            Text('${row.court.name} · ${row.court.sport}'),
            const SizedBox(height: 16),
            Text(
              'Inicio: ${venueTime(row.booking.startsAt, row.venue.timezone)}',
            ),
            Text('Fin: ${venueTime(row.booking.endsAt, row.venue.timezone)}'),
            Text('Zona: ${row.venue.timezone}'),
            Text(
              'Estado: ${row.booking.status == 'cancelled' ? 'Cancelada' : 'Confirmada'}',
            ),
            const SizedBox(height: 24),
            if (row.booking.canCancel)
              FilledButton(
                onPressed: _busy ? null : () => _cancel(refresh),
                child: Text(_busy ? 'Cancelando…' : 'Cancelar reserva'),
              ),
            if (!row.booking.canCancel && row.booking.status == 'confirmed')
              const Text('La reserva ya comenzó y no se puede cancelar.'),
          ],
        ),
      ),
    ),
  );
}

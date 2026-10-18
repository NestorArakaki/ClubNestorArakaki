import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/async_view.dart';
import 'availability_screen.dart';

class VenuesScreen extends StatelessWidget {
  const VenuesScreen({super.key, required this.api});
  final ApiClient api;
  @override
  Widget build(BuildContext context) => AsyncView<List<Venue>>(
    load: api.venues,
    builder: (venues, refresh) => RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Elegí una sede',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (venues.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Todavía no hay sedes cargadas.'),
            ),
          for (final venue in venues)
            Card(
              child: ListTile(
                title: Text(venue.name),
                subtitle: Text(venue.address),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => VenueScreen(api: api, venue: venue),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class VenueScreen extends StatelessWidget {
  const VenueScreen({super.key, required this.api, required this.venue});
  final ApiClient api;
  final Venue venue;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(venue.name)),
    body: AsyncView<(List<Court>, List<OpeningHour>)>(
      load: () async {
        final courts = await api.courts(venue.id);
        final hours = await api.hours(venue.id);
        return (courts, hours);
      },
      builder: (data, refresh) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(venue.address),
            Text('Zona horaria: ${venue.timezone}'),
            const SizedBox(height: 16),
            Text(
              'Horarios de apertura',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (var day = 0; day < 7; day++) _opening(day, data.$2),
            const SizedBox(height: 16),
            Text('Canchas', style: Theme.of(context).textTheme.titleLarge),
            if (data.$1.isEmpty)
              const Text('No hay canchas activas en esta sede.'),
            for (final court in data.$1)
              Card(
                child: ListTile(
                  title: Text(court.name),
                  subtitle: Text(court.sport),
                  trailing: const Icon(Icons.calendar_month),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => AvailabilityScreen(
                        api: api,
                        venue: venue,
                        court: court,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
  Widget _opening(int day, List<OpeningHour> hours) {
    const days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    final rows = hours.where((h) => h.weekday == day);
    final text = rows.isEmpty
        ? 'Cerrado'
        : '${rows.first.open.toString().padLeft(2, '0')}:00–${rows.first.close.toString().padLeft(2, '0')}:00';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text('${days[day]}: $text'),
    );
  }
}

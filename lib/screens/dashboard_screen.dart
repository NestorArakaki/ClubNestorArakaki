import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../widgets/async_view.dart';
import '../widgets/booking_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/venue_card.dart';
import 'bookings_screen.dart';
import 'venues_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.onExplore,
  });
  final ApiClient api;
  final VoidCallback onExplore;

  Future<(Profile, List<Venue>, List<BookingInfo>)> _load() async {
    final data = await Future.wait<Object>([
      api.profile(),
      api.venues(),
      api.bookingInfo('all'),
    ]);
    return (
      data[0] as Profile,
      data[1] as List<Venue>,
      data[2] as List<BookingInfo>,
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => AsyncView<(Profile, List<Venue>, List<BookingInfo>)>(
    load: _load,
    builder: (data, refresh) {
      final (profile, venues, allBookings) = data;
      final now = DateTime.now();
      final upcoming =
          allBookings.where((row) => row.booking.isUpcomingAt(now)).toList()
            ..sort((a, b) => a.booking.startsAt.compareTo(b.booking.startsAt));
      final scheme = Theme.of(context).colorScheme;
      final name = profile.firstName.trim();
      Future<void> open(Widget screen) async {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => screen),
        );
        if (context.mounted) await refresh();
      }

      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sports_tennis, size: 36, color: scheme.secondary),
                  const SizedBox(height: 16),
                  Text(
                    'TU CLUB. TU CANCHA.',
                    style: TextStyle(
                      color: scheme.secondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name.isEmpty ? '¡Hola!' : 'Hola, $name',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Encontrá tu lugar para jugar.',
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(color: scheme.onPrimary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (upcoming.isEmpty)
              Card(
                child: EmptyState(
                  icon: Icons.event_available,
                  title: 'Tu próximo partido te espera',
                  message: 'Todavía no tenés reservas próximas. Elegí una sede y encontrá tu horario.',
                  action: FilledButton.icon(
                    onPressed: onExplore,
                    icon: const Icon(Icons.search),
                    label: const Text('Explorar sedes'),
                  ),
                ),
              )
            else ...[
              Text(
                upcoming.first.booking.phaseAt(now) == BookingPhase.inProgress
                    ? 'Tu reserva en curso'
                    : 'Tu próxima reserva',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              BookingCard(
                row: upcoming.first,
                onTap: () => open(
                  BookingDetailScreen(
                    api: api,
                    bookingId: upcoming.first.booking.id,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onExplore,
                icon: const Icon(Icons.search),
                label: const Text('Explorar sedes'),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Sedes para jugar',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (venues.isEmpty)
              const EmptyState(
                icon: Icons.stadium_outlined,
                title: 'Todavía no hay sedes cargadas.',
                message: 'Cuando estén disponibles, las vas a encontrar acá.',
              ),
            for (final venue in venues)
              VenueCard(
                venue: venue,
                onTap: () => open(VenueScreen(api: api, venue: venue)),
              ),
          ],
        ),
      );
    },
  );
}

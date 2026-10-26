import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/formatters.dart';

class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.phase});
  final BookingPhase phase;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, foreground, background) = switch (phase) {
      BookingPhase.upcoming => (
        'Confirmada',
        Icons.check_circle_outline,
        const Color(0xFF2D5B15),
        const Color(0xFFE6F2C8),
      ),
      BookingPhase.inProgress => (
        'En curso',
        Icons.play_circle_outline,
        const Color(0xFF1555A0),
        const Color(0xFFE5EFFF),
      ),
      BookingPhase.finished => (
        'Finalizada',
        Icons.task_alt,
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
      BookingPhase.cancelled => (
        'Cancelada',
        Icons.cancel_outlined,
        scheme.error,
        scheme.errorContainer,
      ),
    };
    return Semantics(
      label: 'Estado de la reserva: $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.row, required this.onTap});
  final BookingInfo row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BookingStatusBadge(phase: row.booking.phaseAt(DateTime.now())),
                Text(
                  'Reserva #${row.booking.id}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '${row.venue.name} · ${row.court.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(sportLabel(row.court.sport)),
            const SizedBox(height: 12),
            Text(venueTime(row.booking.startsAt, row.venue.timezone)),
            Text('Hasta ${venueTime(row.booking.endsAt, row.venue.timezone)}'),
            const SizedBox(height: 12),
            const Row(
              children: [
                Text('Ver reserva'),
                SizedBox(width: 6),
                Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

typedef Json = Map<String, dynamic>;

class Venue {
  Venue.fromJson(Json j)
    : id = j['id'] as int,
      name = j['name'] as String,
      address = j['address'] as String,
      timezone = j['timezone'] as String;
  final int id;
  final String name, address, timezone;
}

class Court {
  Court.fromJson(Json j)
    : id = j['id'] as int,
      venueId = j['venue_id'] as int,
      name = j['name'] as String,
      sport = j['sport'] as String,
      active = j['active'] as bool;
  final int id, venueId;
  final String name, sport;
  final bool active;
}

class OpeningHour {
  OpeningHour.fromJson(Json j)
    : weekday = j['weekday'] as int,
      open = j['open_hour'] as int,
      close = j['close_hour'] as int;
  final int weekday, open, close;
}

class Slot {
  Slot.fromJson(Json j)
    : startsAt = DateTime.parse(j['starts_at'] as String),
      endsAt = DateTime.parse(j['ends_at'] as String),
      available = j['available'] as bool;
  final DateTime startsAt, endsAt;
  final bool available;
}

class Availability {
  Availability.fromJson(Json j)
    : timezone = j['timezone'] as String,
      slots = (j['slots'] as List)
          .map((s) => Slot.fromJson(s as Json))
          .toList();
  final String timezone;
  final List<Slot> slots;

  // Sólo ofrece duraciones compuestas por bloques contiguos disponibles.
  int maxDuration(int index) {
    var hours = 0;
    for (var i = index; i < slots.length && hours < 24; i++) {
      if (!slots[i].available ||
          (i > index && slots[i - 1].endsAt != slots[i].startsAt)) {
        break;
      }
      hours++;
    }
    return hours;
  }
}

enum BookingPhase { upcoming, inProgress, finished, cancelled }

class Booking {
  Booking.fromJson(Json j)
    : id = j['id'] as int,
      courtId = j['court_id'] as int,
      startsAt = DateTime.parse(j['starts_at'] as String),
      endsAt = DateTime.parse(j['ends_at'] as String),
      status = j['status'] as String;
  final int id, courtId;
  final DateTime startsAt, endsAt;
  final String status;
  bool isUpcomingAt(DateTime now) =>
      status == 'confirmed' && endsAt.isAfter(now);
  BookingPhase phaseAt(DateTime now) {
    if (status == 'cancelled') return BookingPhase.cancelled;
    if (!endsAt.isAfter(now)) return BookingPhase.finished;
    return startsAt.isAfter(now)
        ? BookingPhase.upcoming
        : BookingPhase.inProgress;
  }

  bool get canCancel => isUpcomingAt(DateTime.now());
}

class Profile {
  Profile.fromJson(Json j)
    : email = j['email'] as String?,
      firstName = j['first_name'] as String? ?? '',
      lastName = j['last_name'] as String? ?? '',
      birthDate = j['birth_date'] as String?;
  final String? email, birthDate;
  final String firstName, lastName;
}

class BookingInfo {
  const BookingInfo(this.booking, this.court, this.venue);
  final Booking booking;
  final Court court;
  final Venue venue;
}

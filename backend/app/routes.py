import sqlalchemy as sa
from flask import g
from flask.views import MethodView
from flask_smorest import Blueprint

from .auth import login_required
from .extensions import db
from .models import Booking, Court, OpeningHour, Venue
from .schemas import (
    AvailabilityQuery,
    AvailabilitySchema,
    BookingCreateSchema,
    BookingPageSchema,
    BookingQuery,
    BookingSchema,
    CourtPageSchema,
    CourtSchema,
    ErrorSchema,
    HealthSchema,
    OpeningHourSchema,
    Pagination,
    ProfilePatchSchema,
    ProfileSchema,
    VenuePageSchema,
    VenueSchema,
)
from .services import availability, cancel_booking, create_booking, get_or_404, utcnow

blp = Blueprint("club", __name__, url_prefix="/api/v1", description="ClubNestorArakaki")
SECURITY = [{"FirebaseAuth": []}]


def page(query, args):
    result = db.paginate(query, page=args["page"], per_page=args["per_page"], error_out=False)
    return {
        "items": result.items,
        "page": result.page,
        "per_page": result.per_page,
        "total": result.total,
    }


@blp.route("/health")
@blp.response(200, HealthSchema)
@blp.alt_response(503, schema=ErrorSchema)
def health():
    """Comprueba el proceso y la conexión PostgreSQL."""
    db.session.execute(sa.text("SELECT 1"))
    return {"status": "ok"}


@blp.route("/venues")
class Venues(MethodView):
    @blp.arguments(Pagination, location="query")
    @blp.response(200, VenuePageSchema)
    def get(self, args):
        """Listar sedes deportivas."""
        return page(sa.select(Venue).order_by(Venue.id), args)


@blp.route("/venues/<int:venue_id>")
class VenueDetail(MethodView):
    @blp.response(200, VenueSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    def get(self, venue_id):
        """Consultar una sede y su zona horaria."""
        return get_or_404(Venue, venue_id)


@blp.route("/venues/<int:venue_id>/courts")
class Courts(MethodView):
    @blp.arguments(Pagination, location="query")
    @blp.response(200, CourtPageSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    def get(self, args, venue_id):
        """Listar canchas activas por sede. Consultar disponibilidad para elegir un turno."""
        get_or_404(Venue, venue_id)
        return page(
            sa.select(Court)
            .where(Court.venue_id == venue_id, Court.active.is_(True))
            .order_by(Court.id),
            args,
        )


@blp.route("/courts/<int:court_id>")
class CourtDetail(MethodView):
    @blp.response(200, CourtSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    def get(self, court_id):
        """Consultar una cancha."""
        return get_or_404(Court, court_id)


@blp.route("/venues/<int:venue_id>/opening-hours")
class OpeningHours(MethodView):
    @blp.response(200, OpeningHourSchema(many=True))
    @blp.alt_response(404, schema=ErrorSchema)
    def get(self, venue_id):
        """Horarios semanales locales; un día ausente está cerrado."""
        get_or_404(Venue, venue_id)
        return db.session.scalars(
            sa.select(OpeningHour)
            .where(OpeningHour.venue_id == venue_id)
            .order_by(OpeningHour.weekday)
        ).all()


@blp.route("/courts/<int:court_id>/availability")
class Availability(MethodView):
    @blp.arguments(AvailabilityQuery, location="query")
    @blp.response(200, AvailabilitySchema)
    @blp.alt_response(404, schema=ErrorSchema)
    @blp.alt_response(422, schema=ErrorSchema)
    def get(self, args, court_id):
        """Disponibilidad en bloques de una hora para una fecha local YYYY-MM-DD.

        Es una consulta informativa: POST /bookings vuelve a validar la reserva de forma atómica.
        No se exponen datos de los usuarios que ocuparon un turno.
        """
        return availability(court_id, args["date"])


@blp.route("/me")
class Profile(MethodView):
    @login_required
    @blp.doc(security=SECURITY)
    @blp.response(200, ProfileSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    @blp.alt_response(503, schema=ErrorSchema)
    def get(self):
        """Obtener el perfil propio; se crea en el primer acceso autenticado."""
        return g.user

    @login_required
    @blp.doc(security=SECURITY)
    @blp.arguments(ProfilePatchSchema)
    @blp.response(200, ProfileSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    @blp.alt_response(422, schema=ErrorSchema)
    def patch(self, data):
        """Editar nombre, apellido y fecha de nacimiento. El email es de Firebase."""
        for key, value in data.items():
            setattr(g.user, key, value.strip() if isinstance(value, str) else value)
        db.session.commit()
        return g.user


@blp.route("/bookings")
class Bookings(MethodView):
    @login_required
    @blp.doc(security=SECURITY)
    @blp.arguments(BookingCreateSchema)
    @blp.response(201, BookingSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    @blp.alt_response(409, schema=ErrorSchema)
    @blp.alt_response(422, schema=ErrorSchema)
    def post(self, data):
        """Reservar una cancha por una o más horas enteras consecutivas.

        Si otra solicitud ocupa el intervalo, responde 409 booking_conflict.
        """
        return create_booking(g.user.id, data)

    @login_required
    @blp.doc(security=SECURITY)
    @blp.arguments(BookingQuery, location="query")
    @blp.response(200, BookingPageSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    def get(self, args):
        """Listar reservas propias futuras/en curso, pasadas o todas; incluye canceladas.

        future: ends_at > ahora; past: ends_at <= ahora. status permite filtrar canceladas.
        """
        query = sa.select(Booking).where(Booking.user_id == g.user.id)
        if args["period"] == "future":
            query = query.where(Booking.ends_at > utcnow())
        elif args["period"] == "past":
            query = query.where(Booking.ends_at <= utcnow())
        if args["status"] == "confirmed":
            query = query.where(Booking.cancelled_at.is_(None))
        elif args["status"] == "cancelled":
            query = query.where(Booking.cancelled_at.is_not(None))
        return page(query.order_by(Booking.starts_at, Booking.id), args)


@blp.route("/bookings/<int:booking_id>")
class BookingDetail(MethodView):
    @login_required
    @blp.doc(security=SECURITY)
    @blp.response(200, BookingSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    def get(self, booking_id):
        """Obtener una reserva propia. Una reserva ajena responde 404."""
        booking = db.session.scalar(
            sa.select(Booking).where(Booking.id == booking_id, Booking.user_id == g.user.id)
        )
        if booking is None:
            from .errors import ApiError

            raise ApiError(404, "not_found", "La reserva solicitada no existe.")
        return booking

    @login_required
    @blp.doc(security=SECURITY)
    @blp.response(200, BookingSchema)
    @blp.alt_response(401, schema=ErrorSchema)
    @blp.alt_response(404, schema=ErrorSchema)
    @blp.alt_response(409, schema=ErrorSchema)
    def delete(self, booking_id):
        """Cancelar una reserva propia futura y liberar el turno. Es idempotente."""
        return cancel_booking(g.user.id, booking_id)

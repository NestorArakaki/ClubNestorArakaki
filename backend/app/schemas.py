import re
from datetime import date

from marshmallow import Schema, ValidationError, fields, validate, validates


class ISODate(fields.Date):
    def _deserialize(self, value, attr, data, **kwargs):
        if not isinstance(value, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
            raise ValidationError("Usá el formato YYYY-MM-DD.")
        return super()._deserialize(value, attr, data, **kwargs)


class Pagination(Schema):
    page = fields.Integer(load_default=1, validate=validate.Range(min=1))
    per_page = fields.Integer(load_default=20, validate=validate.Range(min=1, max=100))


class VenueSchema(Schema):
    id = fields.Integer(dump_only=True)
    name = fields.String()
    address = fields.String()
    timezone = fields.String()


class CourtSchema(Schema):
    id = fields.Integer(dump_only=True)
    venue_id = fields.Integer()
    name = fields.String()
    sport = fields.String()
    active = fields.Boolean()


class OpeningHourSchema(Schema):
    weekday = fields.Integer(metadata={"description": "Lunes=0, domingo=6. Día ausente=cerrado."})
    open_hour = fields.Integer()
    close_hour = fields.Integer(
        metadata={"description": "24 equivale a medianoche del día siguiente."}
    )


class ProfileSchema(Schema):
    id = fields.Integer(dump_only=True)
    email = fields.Email(allow_none=True, dump_only=True)
    first_name = fields.String(allow_none=True)
    last_name = fields.String(allow_none=True)
    birth_date = ISODate(allow_none=True)


class ProfilePatchSchema(Schema):
    first_name = fields.String(validate=validate.Length(min=1, max=100))
    last_name = fields.String(validate=validate.Length(min=1, max=100))
    birth_date = ISODate(allow_none=True)

    @validates("first_name", "last_name")
    def non_blank(self, value, **kwargs):
        if not value.strip():
            raise ValidationError("No puede estar vacío.")

    @validates("birth_date")
    def valid_birth(self, value, **kwargs):
        if value and not date(1900, 1, 1) <= value <= date.today():
            raise ValidationError("La fecha debe estar entre 1900-01-01 y hoy.")


class BookingCreateSchema(Schema):
    court_id = fields.Integer(required=True, strict=True, validate=validate.Range(min=1))
    starts_at = fields.DateTime(
        required=True,
        metadata={
            "description": "ISO 8601 con zona u offset; comienzo en hora local exacta.",
            "example": "2026-12-20T18:00:00-03:00",
        },
    )
    duration_hours = fields.Integer(
        required=True, strict=True, validate=validate.Range(min=1, max=24)
    )


class BookingSchema(Schema):
    id = fields.Integer()
    court_id = fields.Integer()
    starts_at = fields.DateTime()
    ends_at = fields.DateTime()
    created_at = fields.DateTime()
    cancelled_at = fields.DateTime(allow_none=True)
    status = fields.String()


class BookingQuery(Pagination):
    period = fields.String(
        load_default="future", validate=validate.OneOf(["future", "past", "all"])
    )
    status = fields.String(
        load_default="all", validate=validate.OneOf(["all", "confirmed", "cancelled"])
    )


class AvailabilityQuery(Schema):
    date = ISODate(required=True)

    @validates("date")
    def supported_date(self, value, **kwargs):
        if value.year >= 9999:
            raise ValidationError("La fecha debe ser anterior al año 9999.")


class SlotSchema(Schema):
    starts_at = fields.DateTime()
    ends_at = fields.DateTime()
    available = fields.Boolean()


class AvailabilitySchema(Schema):
    court_id = fields.Integer()
    date = ISODate()
    timezone = fields.String()
    slots = fields.List(fields.Nested(SlotSchema))


class PageSchema(Schema):
    page = fields.Integer()
    per_page = fields.Integer()
    total = fields.Integer()


class VenuePageSchema(PageSchema):
    items = fields.List(fields.Nested(VenueSchema))


class CourtPageSchema(PageSchema):
    items = fields.List(fields.Nested(CourtSchema))


class BookingPageSchema(PageSchema):
    items = fields.List(fields.Nested(BookingSchema))


class ErrorDetailSchema(Schema):
    code = fields.String()
    message = fields.String()
    details = fields.Dict()


class ErrorSchema(Schema):
    error = fields.Nested(ErrorDetailSchema)


class HealthSchema(Schema):
    status = fields.String()

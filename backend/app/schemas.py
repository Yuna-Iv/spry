import uuid
from datetime import UTC, date, datetime
from typing import Annotated

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    StringConstraints,
    field_serializer,
    model_validator,
)

NonEmptyStr = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1)]


def _require_tz(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("datetime must include a time-zone offset")
    return value.astimezone(UTC)


AwareDatetime = Annotated[datetime, AfterValidator(_require_tz)]


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    email: str
    name: str


class ParticipantCreate(BaseModel):
    name: Annotated[NonEmptyStr, StringConstraints(max_length=100)]
    email: Annotated[EmailStr, StringConstraints(max_length=255)]


class ParticipantRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    email: str


class MeetingCreate(BaseModel):
    title: Annotated[NonEmptyStr, StringConstraints(max_length=200)]
    description: str = ""
    starts_at: AwareDatetime
    ends_at: AwareDatetime
    place: Annotated[NonEmptyStr, StringConstraints(max_length=200)]
    participant_ids: list[uuid.UUID] = []

    @model_validator(mode="after")
    def check_times(self) -> MeetingCreate:
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        # de-duplicate while keeping order
        self.participant_ids = list(dict.fromkeys(self.participant_ids))
        return self


class MeetingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    title: str
    description: str
    starts_at: datetime
    ends_at: datetime
    place: str
    participants: list[ParticipantRead]
    created_at: datetime

    @field_serializer("starts_at", "ends_at", "created_at")
    def to_utc(self, value: datetime) -> str:
        return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


# --- Agenda -------------------------------------------------------------------------------
# One contract for the hand-typed agenda and for the agenda parser (app/ai/agenda.py), which
# reuses AgendaItem and ActionItem in the JSON schema it gives the model.

OptionalName = Annotated[str, StringConstraints(strip_whitespace=True, max_length=255)] | None


class AgendaItem(BaseModel):
    topic: Annotated[NonEmptyStr, StringConstraints(max_length=300)]
    owner: OptionalName = None  # a name or an email, exactly as written
    minutes: int | None = Field(default=None, ge=1, le=480)


class ActionItem(BaseModel):
    task: Annotated[NonEmptyStr, StringConstraints(max_length=300)]
    owner: OptionalName = None
    due: date | None = None


class AiSuggestion(BaseModel):
    """What the parser proposed, stored as-is next to the saved agenda."""

    agenda: dict
    model: Annotated[str, StringConstraints(max_length=100)]
    prompt_version: Annotated[str, StringConstraints(max_length=50)]
    source_text: Annotated[str, StringConstraints(max_length=10_000)]


class AgendaSave(BaseModel):
    items: list[AgendaItem] = Field(max_length=50)
    action_items: list[ActionItem] = Field(default=[], max_length=50)
    ai_suggestion: AiSuggestion | None = None


class AgendaRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    items: list[AgendaItem]
    action_items: list[ActionItem]
    from_ai: bool = False
    updated_at: datetime | None = None

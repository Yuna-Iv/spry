"""The agenda parser on AWS Lambda, behind a public function URL (infra/ai.yml).

It runs the backend's container image, like the report builder, with this small app instead of
the API: Lambda Web Adapter (already in the image) passes each function-URL request to uvicorn.
The function is outside the VPC and never touches the database: it receives text and returns
JSON. Saving goes through the main API (PUT /api/meetings/{id}/agenda), never through here.

Every call costs money, so every request needs a Cognito ID token, and long texts are rejected
before the model is called. One JSON log line per parse: user, model, prompt version, tokens,
latency and cost. CORS is set on the function URL, not here (both would duplicate the headers).
"""

import asyncio
import json
import time
from datetime import date
from typing import Annotated

import anthropic
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import BaseModel

from app.ai.agenda import (
    PROMPT_VERSION,
    AgendaParseError,
    ParsedAgenda,
    cost_usd,
    parse_agenda,
)
from app.auth import InvalidTokenError, TokenVerifier, bearer, get_verifier
from app.config import settings

MAX_CHARS = 10_000

app = FastAPI(title="Agenda parser", docs_url=None, redoc_url=None, openapi_url=None)


class ParseRequest(BaseModel):
    text: str
    today: date  # the user's date and time zone: "Monday" is theirs, not the function's (UTC)
    tz: str


def log(event: str, **fields) -> None:
    """One JSON line per event; CloudWatch filters on fields: { $.event = "agenda_parsed" }."""
    print(json.dumps({"event": event, **fields}, ensure_ascii=False), flush=True)


async def current_user_sub(
    verifier: Annotated[TokenVerifier, Depends(get_verifier)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> str:
    if credentials is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Not authenticated")
    try:
        claims = await verifier.verify(credentials.credentials)
    except InvalidTokenError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token") from None
    return claims["sub"]


@app.get("/health")
async def health() -> dict[str, str]:
    # Lambda Web Adapter waits for this before passing on the first request.
    return {"status": "ok"}


@app.post("/parse")
async def parse(body: ParseRequest, user: Annotated[str, Depends(current_user_sub)]) -> dict:
    if len(body.text) > MAX_CHARS:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE, f"The text is longer than {MAX_CHARS} characters"
        )
    if settings.parser_fake:
        await asyncio.sleep(3)
        log("agenda_parsed", user=user, model="fake", prompt_version=PROMPT_VERSION)
        return {"agenda": fake_agenda(), "model": "fake", "prompt_version": "fake"}

    started = time.monotonic()
    fields = {"user": user, "model": settings.parser_model, "prompt_version": PROMPT_VERSION}
    try:
        # The SDK call blocks; run it in a thread so the event loop stays free.
        agenda, usage = await asyncio.to_thread(parse_agenda, body.text, body.today, body.tz)
    except AgendaParseError as e:
        log(
            "agenda_parse_failed",
            **fields,
            **e.usage,
            latency_ms=int((time.monotonic() - started) * 1000),
            cost_usd=cost_usd(settings.parser_model, e.usage),
            error=str(e),
        )
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_CONTENT, str(e)) from None
    except anthropic.RateLimitError:
        log("agenda_parse_throttled", **fields)
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "The AI service is busy; try again in a minute"
        ) from None
    except anthropic.APIError as e:
        log("agenda_parse_error", **fields, error=type(e).__name__, detail=str(e)[:500])
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "The AI service is not available right now"
        ) from None

    log(
        "agenda_parsed",
        **fields,
        **usage,
        latency_ms=int((time.monotonic() - started) * 1000),
        cost_usd=cost_usd(settings.parser_model, usage),
    )
    return {
        "agenda": agenda.model_dump(mode="json"),
        "model": settings.parser_model,
        "prompt_version": PROMPT_VERSION,
    }


def fake_agenda() -> dict:
    """The introduction's example, as the model would parse it (PARSER_FAKE=true only)."""
    return ParsedAgenda.model_validate(
        {
            "title": "Синк по прайсингу",
            "starts_at": None,
            "duration_minutes": 45,
            "items": [
                {"topic": "Нові тарифи Pro", "owner": "Олена", "minutes": 15},
                {"topic": "Фідбек від клієнтів", "owner": "Taras"},
                {"topic": "Що робимо з річною знижкою"},
            ],
            "action_items": [
                {"task": "Зібрати порівняння з конкурентами", "owner": "Taras", "due": None}
            ],
            "language": "uk",
        }
    ).model_dump(mode="json")

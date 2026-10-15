"""The weekly meetings report: one ISO week of meetings as a CSV file.

There is no AWS in this module. It reads the database and returns bytes, so it runs and is
tested locally:

    python -m app.reports.weekly 2026-W40 > report.csv

The Lambda handlers in lambda_app.py decide which week to build and where the file goes.
Two rules the rest of the pipeline relies on:

- The week is always a parameter. Nothing here means "last week"; the caller decides.
- The same week always gets the same file name (report_key), so building a week twice
  overwrites one file. That makes the build idempotent, and "at least once" delivery harmless.
"""

import asyncio
import csv
import io
import re
import sys
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.db import SessionLocal
from app.models import Meeting, User

WEEK_PATTERN = re.compile(r"^(\d{4})-W(\d{2})$")
LONGEST_COUNT = 5


def week_start(week: str) -> datetime:
    """Monday 00:00 UTC of an ISO week written like "2026-W40"."""
    match = WEEK_PATTERN.match(week)
    if not match:
        raise ValueError(f"Expected a week like 2026-W40, got {week!r}")
    # Raises ValueError for a week that does not exist, e.g. 2026-W60.
    monday = date.fromisocalendar(int(match[1]), int(match[2]), 1)
    return datetime(monday.year, monday.month, monday.day, tzinfo=UTC)


def week_of(day: date) -> str:
    year, number, _ = day.isocalendar()
    return f"{year}-W{number:02d}"


def previous_week(week: str) -> str:
    return week_of((week_start(week) - timedelta(days=7)).date())


def last_week(today: date | None = None) -> str:
    """The ISO week before the one that contains `today` (today in UTC by default)."""
    today = today or datetime.now(UTC).date()
    return week_of(today - timedelta(days=7))


def report_key(week: str) -> str:
    """The S3 key of a week's report. Same week, same key."""
    week_start(week)  # validates the week
    return f"reports/{week}.csv"


def hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


async def load_meetings(session: AsyncSession, week: str) -> list[tuple[Meeting, str]]:
    """Meetings that start in the week, each with its organiser's email."""
    start = week_start(week)
    end = start + timedelta(days=7)
    result = await session.execute(
        select(Meeting, User.email)
        .join(User, Meeting.owner_id == User.id)
        .options(selectinload(Meeting.participants))
        .where(Meeting.starts_at >= start, Meeting.starts_at < end)
        .order_by(Meeting.starts_at)
    )
    return [(meeting, email) for meeting, email in result.all()]


def write_csv(
    week: str, current: list[tuple[Meeting, str]], before: list[tuple[Meeting, str]]
) -> bytes:
    start = week_start(week)
    current_hours = sum(hours(meeting) for meeting, _ in current)
    before_hours = sum(hours(meeting) for meeting, _ in before)

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")

    writer.writerow(["Weekly meetings report", week])
    end_day = (start + timedelta(days=6)).date()
    writer.writerow(["Period (UTC)", start.date().isoformat(), end_day.isoformat()])
    writer.writerow([])

    writer.writerow(["Week", "Meetings", "Hours"])
    writer.writerow([week, len(current), f"{current_hours:.2f}"])
    writer.writerow([previous_week(week), len(before), f"{before_hours:.2f}"])
    writer.writerow(
        ["Change", f"{len(current) - len(before):+d}", f"{current_hours - before_hours:+.2f}"]
    )
    writer.writerow([])

    writer.writerow([f"{LONGEST_COUNT} longest meetings"])
    writer.writerow(["Title", "Starts at (UTC)", "Hours", "Participants"])
    longest = sorted(current, key=lambda row: (-hours(row[0]), row[0].starts_at))
    for meeting, _ in longest[:LONGEST_COUNT]:
        writer.writerow(
            [
                meeting.title,
                meeting.starts_at.astimezone(UTC).strftime("%Y-%m-%d %H:%M"),
                f"{hours(meeting):.2f}",
                len(meeting.participants),
            ]
        )
    writer.writerow([])

    writer.writerow(["Per organiser"])
    writer.writerow(["Organiser", "Meetings", "Hours"])
    per_person: dict[str, list[float]] = {}
    for meeting, email in current:
        per_person.setdefault(email, []).append(hours(meeting))
    for email, durations in sorted(per_person.items(), key=lambda item: (-sum(item[1]), item[0])):
        writer.writerow([email, len(durations), f"{sum(durations):.2f}"])

    # The BOM lets Excel open the file with Cyrillic titles intact.
    return out.getvalue().encode("utf-8-sig")


async def build_weekly_report(week: str, session: AsyncSession | None = None) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    week_start(week)  # fail fast on a bad week, before touching the database
    if session is None:
        async with SessionLocal() as own_session:
            return await build_weekly_report(week, own_session)
    current = await load_meetings(session, week)
    before = await load_meetings(session, previous_week(week))
    return write_csv(week, current, before)


if __name__ == "__main__":
    # python -m app.reports.weekly [2026-W40]   (default: last week)
    chosen = sys.argv[1] if len(sys.argv) > 1 else last_week()
    sys.stdout.buffer.write(asyncio.run(build_weekly_report(chosen)))

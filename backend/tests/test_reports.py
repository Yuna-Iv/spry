import csv
import io
import json
from datetime import UTC, date, datetime, timedelta

from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Base, Meeting, Participant, User
from app.reports import lambda_app
from app.reports.weekly import (
    build_weekly_report,
    last_week,
    previous_week,
    report_key,
    week_start,
)


def test_week_helpers() -> None:
    assert week_start("2026-W40") == datetime(2026, 9, 28, tzinfo=UTC)
    assert previous_week("2026-W01") == "2025-W52"
    # Thursday 15 October 2026 is in W42, so "last week" is W41.
    assert last_week(date(2026, 10, 15)) == "2026-W41"
    assert report_key("2026-W40") == "reports/2026-W40.csv"


async def test_weekly_report(engine) -> None:
    async with engine.begin() as conn:
        for table in reversed(Base.metadata.sorted_tables):
            await conn.execute(table.delete())

    monday = datetime(2026, 9, 28, 9, tzinfo=UTC)  # 2026-W40
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        alice = User(cognito_sub="alice", email="alice@example.com", name="Alice")
        bob = User(cognito_sub="bob", email="bob@example.com", name="Bob")
        olena = Participant(name="Olena", email="olena@example.com")
        session.add_all([alice, bob, olena])
        await session.flush()

        def meeting(owner: User, title: str, start: datetime, hours: float, people=()) -> Meeting:
            return Meeting(
                title=title,
                starts_at=start,
                ends_at=start + timedelta(hours=hours),
                place="Room",
                owner_id=owner.id,
                participants=list(people),
            )

        session.add_all(
            [
                meeting(alice, "Планування", monday, 2, [olena]),
                meeting(alice, "Standup", monday + timedelta(days=1), 0.25),
                meeting(bob, "Review", monday + timedelta(days=2), 1),
                meeting(bob, "Last week", monday - timedelta(days=3), 1.5),
                meeting(bob, "Next week", monday + timedelta(days=7), 3),
            ]
        )
        await session.commit()

        report = await build_weekly_report("2026-W40", session)
        # Same week, same data: the same bytes.
        assert await build_weekly_report("2026-W40", session) == report

    rows = list(csv.reader(io.StringIO(report.decode("utf-8-sig"))))
    assert rows[0] == ["Weekly meetings report", "2026-W40"]
    assert ["2026-W40", "3", "3.25"] in rows
    assert ["2026-W39", "1", "1.50"] in rows
    assert ["Change", "+2", "+1.75"] in rows
    assert ["Планування", "2026-09-28 09:00", "2.00", "1"] in rows
    assert ["alice@example.com", "2", "2.25"] in rows
    assert ["bob@example.com", "1", "1.00"] in rows
    assert not any("Next week" in row for row in rows)


async def test_failed_sqs_message_goes_back_to_the_queue(monkeypatch) -> None:
    async def fail(*args, **kwargs):
        raise RuntimeError("database is asleep")

    monkeypatch.setattr(lambda_app, "build_and_save", fail)
    event = {
        "Records": [
            {
                "eventSource": "aws:sqs",
                "messageId": "m-1",
                "body": json.dumps({"week": "2026-W40", "source": "make"}),
                "attributes": {"ApproximateReceiveCount": "1"},
            }
        ]
    }
    transport = ASGITransport(app=lambda_app.app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post("/events", json=event)
    assert response.json() == {"batchItemFailures": [{"itemIdentifier": "m-1"}]}

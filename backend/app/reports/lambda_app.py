"""The report builder on AWS Lambda.

The builder runs the backend's own container image (same models, same database code), with
this small app instead of the API. Lambda Web Adapter, already in the image, forwards every
non-HTTP event to POST /events:

- an SQS message from the report-requests queue: sent by the weekly schedule or by
  `make report-now`. Body: {"week": "2026-W40" or null, "source": "schedule" | "make"}.
- a direct invocation (aws lambda invoke), with the same JSON as the event itself.

It builds the CSV and saves it as reports/<week>.csv. It never sends email: the bucket's
ObjectCreated event starts the mailer, and the builder does not know the mailer exists.
"""

import json
import os
from typing import Any

import boto3
from fastapi import FastAPI, Request

from app.reports.weekly import build_weekly_report, last_week, report_key

app = FastAPI(title="Report builder")


def log(message: str, **fields: Any) -> None:
    """One JSON line per event, so CloudWatch can filter on fields: { $.trigger = "sqs" }."""
    print(json.dumps({"message": message, **fields}), flush=True)


async def build_and_save(request: dict, trigger: str, via: str) -> str:
    # The caller decides the week; with none, it is the previous ISO week.
    week = request.get("week") or last_week()
    log("report-builder triggered", trigger=trigger, via=via, week=week)

    # Lets you test the dead-letter queue: deploy with REPORT_FAIL_WEEK set and send that week.
    if week == os.environ.get("REPORT_FAIL_WEEK"):
        raise RuntimeError(f"REPORT_FAIL_WEEK is {week}: failing on purpose")

    body = await build_weekly_report(week)
    key = report_key(week)
    boto3.client("s3").put_object(
        Bucket=os.environ["REPORTS_BUCKET"],
        Key=key,
        Body=body,
        ContentType="text/csv; charset=utf-8",
    )
    log("report saved", trigger=trigger, week=week, key=key, size=len(body))
    return key


@app.get("/health")
async def health() -> dict[str, str]:
    # Lambda Web Adapter waits for this before passing on the first event.
    return {"status": "ok"}


@app.post("/events")
async def events(request: Request) -> dict:
    event = await request.json()
    records = [r for r in event.get("Records", []) if r.get("eventSource") == "aws:sqs"]

    if not records:
        # Direct invocation. An exception becomes a 500, which fails the invocation
        # (AWS_LWA_ERROR_STATUS_CODES), and the failure is only a log line.
        key = await build_and_save(event, trigger=event.get("source", "direct"), via="direct")
        return {"key": key}

    # An SQS batch. A failed message is reported back instead of raised: SQS makes it visible
    # again, and after three receives the redrive policy moves it to the dead-letter queue.
    failures = []
    for record in records:
        try:
            body = json.loads(record["body"])
            trigger = "schedule" if body.get("source") == "schedule" else "sqs"
            await build_and_save(body, trigger=trigger, via="sqs")
        except Exception as error:  # noqa: BLE001 - every failure goes back to the queue
            log(
                "report-builder failed",
                message_id=record["messageId"],
                receive_count=record.get("attributes", {}).get("ApproximateReceiveCount"),
                error=str(error),
            )
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}

"""report-mailer: emails a weekly report as soon as it appears in S3.

Triggered by s3:ObjectCreated on reports/*.csv. Runs outside the VPC, so it can reach SES,
and it never touches the database. It only reads from the bucket: a function that writes
into the prefix that triggers it would call itself forever.
"""

import json
import os
import urllib.parse
from email.message import EmailMessage

import boto3

s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def log(message, **fields):
    print(json.dumps({"message": message, **fields}))


def handler(event, context):
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        # Keys arrive URL-encoded ("2026-W40" stays as is, spaces would become "+").
        key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])
        log("report-mailer triggered", trigger="s3", event=record["eventName"], key=key)

        report = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
        file_name = key.rsplit("/", 1)[-1]
        week = file_name.removesuffix(".csv")

        message = EmailMessage()
        message["Subject"] = f"Weekly meetings report {week}"
        message["From"] = os.environ["REPORT_FROM"]
        message["To"] = os.environ["REPORT_TO"]
        message.set_content(f"Hi!\n\nThe meetings report for {week} is attached.\n")
        message.add_attachment(report, maintype="text", subtype="csv", filename=file_name)

        result = ses.send_email(Content={"Raw": {"Data": message.as_bytes()}})
        log("report emailed", key=key, to=os.environ["REPORT_TO"], ses_id=result["MessageId"])

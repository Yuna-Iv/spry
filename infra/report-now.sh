#!/usr/bin/env bash
# Asks for a report now: puts the same message on the queue as the schedule does, with a week.
# Run via `make report-now WEEK=2026-W40` (default: last week).
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  week="${WEEK:-$(python3 -c 'import datetime as d; y, w, _ = (d.date.today() - d.timedelta(7)).isocalendar(); print(f"{y}-W{w:02d}")')}"
  queue="$(tf_output report_queue_url)"
  aws sqs send-message --queue-url "$queue" \
    --message-body "{\"week\": \"$week\", \"source\": \"make\"}" \
    --query MessageId --output text
  echo "Asked for the report of $week. Within a minute:"
  echo "  make report-ls     # the file in S3"
  echo "  make report-logs   # the builder's and the mailer's log lines"
}

main "$@"

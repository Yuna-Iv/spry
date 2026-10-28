#!/usr/bin/env bash
# Prints the agenda parser's log lines of the last 24 hours, one JSON object per parse
# ({ "event": "agenda_parsed", "model": ..., "input_tokens": ..., "cost_usd": ... }).
# Run via `make parser-logs`; one of these lines is item 4 of the lab submission.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  log_group="$(tf_output parser_log_group)"
  since=$(( ($(date +%s) - 24 * 3600) * 1000 ))
  aws logs filter-log-events \
    --log-group-name "$log_group" \
    --start-time "$since" \
    --filter-pattern '{ $.event = "agenda_*" }' \
    --query 'events[].message' --output text | tr '\t' '\n'
}

main "$@"

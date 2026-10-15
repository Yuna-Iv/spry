#!/usr/bin/env bash
# Prints the trigger log lines of the last 24 hours: which event started each function.
# Run via `make report-logs`.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  since=$(( ($(date +%s) - 86400) * 1000 ))
  for group in BuilderLogGroup MailerLogGroup; do
    name="$(output "$REPORTS_STACK" "$group")"
    echo "==> $name"
    aws logs filter-log-events --log-group-name "$name" --start-time "$since" \
      --filter-pattern '"triggered"' \
      --query 'events[].[timestamp, message]' --output text |
      while IFS=$'\t' read -r ts message; do
        printf '%s  %s\n' "$(date -u -d "@$((ts / 1000))" '+%Y-%m-%d %H:%M:%S UTC')" "$message"
      done
  done
}

main "$@"

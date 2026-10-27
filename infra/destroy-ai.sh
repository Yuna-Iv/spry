#!/usr/bin/env bash
# Deletes the agenda parser stack (function, URL, log group and the $5 budget).
# Run via `make destroy-ai` (make destroy-backend runs it first: the parser uses the backend's image).
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  stack_exists "$AI_STACK" || { echo "No $AI_STACK stack."; exit 0; }
  echo "==> Delete $AI_STACK"
  aws cloudformation delete-stack --stack-name "$AI_STACK"
  aws cloudformation wait stack-delete-complete --stack-name "$AI_STACK"
}

main "$@"

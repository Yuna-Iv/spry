#!/usr/bin/env bash
# Deletes the weekly report stack, reports included. Run via `make destroy-reports`
# (make destroy-backend runs it first: its S3 endpoint sits in the backend's VPC).
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  stack_exists "$REPORTS_STACK" || { echo "No $REPORTS_STACK stack."; exit 0; }
  bucket="$(output "$REPORTS_STACK" BucketName)"
  echo "==> Empty s3://$bucket"
  aws s3 rm "s3://$bucket" --recursive >/dev/null || true
  echo "==> Delete $REPORTS_STACK"
  aws cloudformation delete-stack --stack-name "$REPORTS_STACK"
  aws cloudformation wait stack-delete-complete --stack-name "$REPORTS_STACK"
}

main "$@"

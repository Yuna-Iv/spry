#!/usr/bin/env bash
# Deletes the API CloudFront distribution and its certificate (make destroy-api).
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  for stack in "$API_STACK" "$API_CERT_STACK"; do
    if stack_exists "$stack" "$CERT_REGION"; then
      echo "==> Delete $stack"
      aws cloudformation delete-stack --stack-name "$stack" --region "$CERT_REGION"
      aws cloudformation wait stack-delete-complete --stack-name "$stack" --region "$CERT_REGION"
    fi
  done
}

main "$@"

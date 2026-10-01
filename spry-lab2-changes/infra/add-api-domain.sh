#!/usr/bin/env bash
# Puts the backend on its own HTTPS domain (API_DOMAIN_NAME, e.g. api.example.com):
# an ACM certificate in us-east-1 and a CloudFront distribution in front of the Lambda
# function URL. Run via `make add-api-domain` after `make deploy`, then run
# `make deploy-frontend` so the frontend calls the new address.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  domain="${API_DOMAIN_NAME:-}"
  zone="${HOSTED_ZONE_ID:-}"
  [ -n "$domain" ] || { echo "Set API_DOMAIN_NAME in .env first." >&2; exit 1; }
  stack_exists "$BACKEND_STACK" || { echo "Stack $BACKEND_STACK not found; run make deploy first." >&2; exit 1; }

  function_domain="$(output "$BACKEND_STACK" ApiBaseUrl)"
  function_domain="${function_domain#https://}"

  echo "==> [1/2] Certificate for $domain ($API_CERT_STACK in $CERT_REGION)"
  aws cloudformation deploy \
    --stack-name "$API_CERT_STACK" \
    --region "$CERT_REGION" \
    --template-file infra/certificate.yaml \
    --parameter-overrides "ProjectName=$PROJECT_NAME" "DomainName=$domain" "HostedZoneId=$zone" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset >/dev/null &
  deploy_pid=$!

  shown=""
  while kill -0 "$deploy_pid" 2>/dev/null; do
    if [ -z "$shown" ]; then
      arn="$(aws cloudformation describe-stack-resource --stack-name "$API_CERT_STACK" --region "$CERT_REGION" \
        --logical-resource-id Certificate --query StackResourceDetail.PhysicalResourceId \
        --output text 2>/dev/null || true)"
      if [[ "$arn" == arn:* ]]; then
        record="$(aws acm describe-certificate --certificate-arn "$arn" --region "$CERT_REGION" \
          --query "Certificate.DomainValidationOptions[0].ResourceRecord.[Name,Type,Value]" \
          --output text 2>/dev/null || true)"
        if [ -n "$record" ] && [ "$record" != "None" ]; then
          read -r rec_name rec_type rec_value <<<"$record"
          if [ -n "$zone" ]; then
            echo "    Route 53 validation record is created automatically; waiting for ACM..."
          else
            echo "    Add this DNS record at your DNS provider, then wait (usually a few minutes):"
            echo "      $rec_type  $rec_name  ->  $rec_value"
          fi
          shown=1
        fi
      fi
    fi
    sleep 10
  done
  wait "$deploy_pid"
  cert_arn="$(output "$API_CERT_STACK" CertificateArn "$CERT_REGION")"
  echo "    Issued: $cert_arn"

  echo "==> [2/2] CloudFront for the API ($API_STACK), origin $function_domain"
  echo "    The first run creates the distribution and takes about 5 minutes."
  aws cloudformation deploy \
    --stack-name "$API_STACK" \
    --region "$CERT_REGION" \
    --template-file infra/api.yaml \
    --parameter-overrides "ProjectName=$PROJECT_NAME" "ApiDomainName=$domain" \
      "CertificateArn=$cert_arn" "FunctionUrlDomain=$function_domain" "HostedZoneId=$zone" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  echo
  if [ -z "$zone" ]; then
    echo "Point the API domain at CloudFront at your DNS provider:"
    echo "  CNAME  $domain  ->  $(output "$API_STACK" DistributionDomain "$CERT_REGION")"
  fi
  echo "API: https://$domain/api/health"
  echo "Now run: make deploy-frontend   (so the frontend calls https://$domain)"
}

main "$@"

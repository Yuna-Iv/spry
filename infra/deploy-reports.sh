#!/usr/bin/env bash
# Deploys the weekly report (infra/reports.yaml): the bucket, the queue, the schedule and the
# two functions. Run via `make deploy-reports` after `make deploy-backend`: the builder reuses
# the backend's image, database URL, subnets and security group, read from the backend function.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  email="${REPORT_EMAIL:-}"
  if [ -z "$email" ]; then
    echo "REPORT_EMAIL is not set (.env or the GitHub variable); skipping the weekly report."
    exit 0
  fi
  backend="$PROJECT_NAME-backend"
  aws lambda get-function --function-name "$backend" >/dev/null 2>&1 || {
    echo "Function $backend not found; run make deploy-backend first." >&2
    exit 1
  }

  echo "==> [1/2] Read the backend function's settings"
  image="$(aws lambda get-function --function-name "$backend" --query Code.ImageUri --output text)"
  db_url="$(aws lambda get-function-configuration --function-name "$backend" \
    --query Environment.Variables.DATABASE_URL --output text)"
  vpc="$(aws lambda get-function-configuration --function-name "$backend" \
    --query VpcConfig.VpcId --output text)"
  subnets="$(aws lambda get-function-configuration --function-name "$backend" \
    --query VpcConfig.SubnetIds --output text | tr '\t' ',')"
  security_group="$(aws lambda get-function-configuration --function-name "$backend" \
    --query 'VpcConfig.SecurityGroupIds[0]' --output text)"
  # The backend's subnets have no route table of their own, so they use the VPC's main one.
  route_table="$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$vpc" "Name=association.main,Values=true" \
    --query 'RouteTables[0].RouteTableId' --output text)"
  schedule="${REPORT_SCHEDULE:-cron(0 7 ? * MON *)}"
  echo "    Image:    $image"
  echo "    Email:    $email"
  echo "    Schedule: $schedule (Europe/Kyiv)"
  [ -n "${REPORT_FAIL_WEEK:-}" ] && echo "    Fails on purpose for week $REPORT_FAIL_WEEK"

  echo "==> [2/2] Weekly report stack ($REPORTS_STACK)"
  aws cloudformation deploy \
    --stack-name "$REPORTS_STACK" \
    --template-file infra/reports.yaml \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides \
      "ProjectName=$PROJECT_NAME" \
      "ImageUri=$image" \
      "DatabaseUrl=$db_url" \
      "VpcId=$vpc" \
      "SubnetIds=$subnets" \
      "SecurityGroupId=$security_group" \
      "RouteTableId=$route_table" \
      "ReportEmail=$email" \
      "ScheduleExpression=$schedule" \
      "FailWeek=${REPORT_FAIL_WEEK:-}" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  status="$(aws sesv2 get-email-identity --email-identity "$email" \
    --query VerificationStatus --output text 2>/dev/null || echo UNKNOWN)"
  echo
  echo "Bucket: s3://$(output "$REPORTS_STACK" BucketName)/reports/"
  echo "SES identity $email: $status"
  if [ "$status" != "SUCCESS" ]; then
    echo "  Open the email from Amazon Web Services and click the verification link."
  fi
  echo "Next: make report-now   (builds last week's report and emails it)"
}

main "$@"

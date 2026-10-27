#!/usr/bin/env bash
# Deploys the agenda parser (infra/ai.yml): the function, its public URL and the $5 budget.
# Run via `make deploy-ai` after `make deploy-backend`: the parser reuses the backend's image and
# its Cognito settings, read from the backend function.
#
# PARSER_MODEL, BEDROCK_REGION, BEDROCK_API, PARSER_EFFORT, PARSER_FAKE and BUDGET_EMAIL come
# from .env (or GitHub variables). An empty one keeps the stack's current value, so a deploy that
# does not set them (e.g. CI without those variables) never resets the model you chose.
set -euo pipefail

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh

  backend="$PROJECT_NAME-backend"
  aws lambda get-function --function-name "$backend" >/dev/null 2>&1 || {
    echo "Function $backend not found; run make deploy-backend first." >&2
    exit 1
  }

  echo "==> [1/2] Read the backend function's settings"
  image="$(aws lambda get-function --function-name "$backend" --query Code.ImageUri --output text)"
  env_var() {
    aws lambda get-function-configuration --function-name "$backend" \
      --query "Environment.Variables.$1" --output text
  }
  pool_id="$(env_var COGNITO_USER_POOL_ID)"
  client_id="$(env_var COGNITO_CLIENT_ID)"
  jwks="$(env_var COGNITO_JWKS)"
  [ "$jwks" = "None" ] && jwks=""
  origins="$(cors_origins)"

  overrides=(
    "ProjectName=$PROJECT_NAME"
    "ImageUri=$image"
    "CognitoUserPoolId=$pool_id"
    "CognitoClientId=$client_id"
    "CognitoJwks=$jwks"
    "CorsOrigins=$origins"
  )
  # Only the settings that are set; the others keep their current (or default) values.
  add() { [ -z "${2:-}" ] || overrides+=("$1=$2"); }
  add ParserModel "${PARSER_MODEL:-}"
  add BedrockRegion "${BEDROCK_REGION:-}"
  add BedrockApi "${BEDROCK_API:-}"
  add ParserEffort "${PARSER_EFFORT:-}"
  add ParserFake "${PARSER_FAKE:-}"
  add BudgetEmail "${BUDGET_EMAIL:-}"

  echo "    Image:   $image"
  echo "    Model:   ${PARSER_MODEL:-(unchanged)} via ${BEDROCK_API:-(unchanged)} in ${BEDROCK_REGION:-(unchanged)}"
  echo "    CORS:    $origins"
  [ "${PARSER_FAKE:-}" = "true" ] && echo "    PARSER_FAKE=true: returns a fixed agenda, never calls the model"

  echo "==> [2/2] Agenda parser stack ($AI_STACK)"
  aws cloudformation deploy \
    --stack-name "$AI_STACK" \
    --template-file infra/ai.yml \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides "${overrides[@]}" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset

  echo
  echo "Parser URL: $(output "$AI_STACK" ParserUrl)/parse"
  echo "Logs:       $(output "$AI_STACK" LogGroup)   (make parser-logs)"
  if [ -n "${BUDGET_EMAIL:-}" ]; then
    echo "Budget:     \$5/month, alerts to $BUDGET_EMAIL"
  fi
  echo "Next: make deploy-frontend   (builds the app against the parser URL)"
}

main "$@"

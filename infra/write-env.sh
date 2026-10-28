#!/usr/bin/env bash
# Writes the Cognito settings from the Terraform outputs to .env, for local runs (make up,
# make dev-frontend). Run via `make infra-env`. None of them are secrets: the browser gets them.
# (Before Terraform, make deploy-auth did this.)
set -euo pipefail

# set_env KEY VALUE: sets KEY=VALUE in .env, replacing an existing line or appending one.
set_env() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  if grep -q "^$key=" .env; then
    awk -v k="$key" -v v="$value" 'index($0, k "=") == 1 { print k "=" v; next } { print }' .env >"$tmp"
  else
    cat .env >"$tmp"
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
  fi
  cat "$tmp" >.env
  rm -f "$tmp"
}

main() {
  cd "$(dirname "$0")/.."
  source infra/common.sh
  require_terraform

  set_env COGNITO_USER_POOL_ID "$(tf_output cognito_user_pool_id)"
  set_env COGNITO_CLIENT_ID "$(tf_output cognito_client_id)"
  set_env COGNITO_DOMAIN "$(tf_output cognito_domain)"
  set_env COGNITO_GOOGLE_ENABLED "$(tf_output cognito_google_enabled)"
  grep '^COGNITO_' .env
}

main "$@"

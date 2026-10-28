# Shared setup for the infra scripts: credentials and settings come from .env via make.
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID in .env}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY in .env}"
: "${AWS_REGION:?Set AWS_REGION in .env}"
export AWS_DEFAULT_REGION="$AWS_REGION" AWS_PAGER=""
[ -n "${AWS_SESSION_TOKEN:-}" ] || unset AWS_SESSION_TOKEN

# APP_NAME is the old name of the setting and still works.
PROJECT_NAME="${PROJECT_NAME:-${APP_NAME:-meetings}}"
ECR_STACK="$PROJECT_NAME-ecr"
BACKEND_STACK="$PROJECT_NAME-backend"
FRONTEND_STACK="$PROJECT_NAME-frontend"
# CloudFront only accepts certificates from us-east-1.
CERT_STACK="$PROJECT_NAME-certificate"
CERT_REGION="us-east-1"
# The API on its own domain (make add-api-domain): a CloudFront distribution and its certificate.
API_STACK="$PROJECT_NAME-api"
API_CERT_STACK="$PROJECT_NAME-api-certificate"

# Every resource is tagged PROJECT_NAME=<PROJECT_NAME>: explicitly in the templates, via the
# stack tags (which also cover resources CloudFormation creates implicitly), and by the
# scripts for resources created outside CloudFormation.
TAG_KEY="PROJECT_NAME"
STACK_TAGS=("$TAG_KEY=$PROJECT_NAME")

# output STACK KEY [REGION]: prints one CloudFormation stack output (empty if absent).
output() {
  aws cloudformation describe-stacks --stack-name "$1" --region "${3:-$AWS_REGION}" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

# stack_exists STACK [REGION]
stack_exists() {
  aws cloudformation describe-stacks --stack-name "$1" --region "${2:-$AWS_REGION}" >/dev/null 2>&1
}

# cors_origins: the sites allowed to call the API: the CloudFront address and custom domain
# (once the frontend stack exists) plus CORS_ORIGINS_AWS.
cors_origins() {
  local candidates="" origins="" origin
  if stack_exists "$FRONTEND_STACK"; then
    candidates="$(output "$FRONTEND_STACK" AppUrl),$(output "$FRONTEND_STACK" CustomDomainUrl)"
  fi
  # Read line by line rather than word-splitting, so "*" (allow any origin) is not
  # expanded into file names.
  while IFS= read -r origin; do
    origin="${origin//[[:space:]]/}"
    [ -n "$origin" ] && origins="${origins:+$origins,}$origin"
  done < <(echo "$candidates,${CORS_ORIGINS_AWS:-}" | tr ',' '\n')
  echo "${origins:-http://localhost:5173}"
}

# update_backend_cors: points the backend's CORS_ORIGINS at the current frontend addresses.
# Every other backend parameter keeps its previous value.
update_backend_cors() {
  local origins
  origins="$(cors_origins)"
  echo "    CORS origins: $origins"
  aws cloudformation deploy \
    --stack-name "$BACKEND_STACK" \
    --template-file infra/backend.yaml \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides "CorsOrigins=$origins" \
    --tags "${STACK_TAGS[@]}" \
    --no-fail-on-empty-changeset
}

# infra_notice: Cognito's redirect URLs and the parser's CORS origins follow the frontend's
# addresses too, but they are Terraform resources now (infra/auth.tf, infra/ai.tf): the next
# HCP Terraform run reads the new addresses from the frontend stack and updates them.
infra_notice() {
  echo "    Cognito redirect URLs and the parser's CORS origins are managed by Terraform:"
  echo "    start a run in HCP Terraform (or merge any change to infra/) to pick up the new addresses."
}

# tf_output NAME: one output of the Terraform configuration in infra/ (Cognito, the weekly
# report, the agenda parser). Needs `terraform login` (laptop) or TF_TOKEN_app_terraform_io (CI).
tf_output() {
  terraform -chdir=infra output -raw "$1"
}

# require_terraform: exits with a hint when the Terraform outputs cannot be read.
require_terraform() {
  command -v terraform >/dev/null || { echo "terraform is not installed (see README)." >&2; exit 1; }
  [ -d infra/.terraform ] || terraform -chdir=infra init -input=false >/dev/null
  tf_output cognito_user_pool_id >/dev/null || {
    echo "Cannot read the Terraform outputs: run terraform login, then make infra-init." >&2
    exit 1
  }
}

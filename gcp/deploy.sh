#!/usr/bin/env bash
# Deploy Spry's core to Google Cloud: the backend image to Cloud Run, the frontend to Firebase Hosting.
# The infrastructure itself (Cloud SQL, secrets, the service) is in gcp/*.tf; run
# `terraform -chdir=gcp apply` once before the first deploy.
set -euo pipefail
cd "$(dirname "$0")/.."

TF="terraform -chdir=gcp"
REPO=$($TF output -raw image_repository)      # us-central1-docker.pkg.dev/<project>/spry
PROJECT_ID=$(echo "$REPO" | cut -d/ -f2)
TAG=$(git rev-parse --short HEAD 2>/dev/null || date +%s)
IMAGE="$REPO/api:$TAG"

echo "==> Backend image $IMAGE"
gcloud auth configure-docker "${REPO%%/*}" --quiet
# Cloud Run runs linux/amd64 only. --target base: the image without the Lambda adapter.
docker build --platform linux/amd64 --provenance=false --target base --tag "$IMAGE" backend
docker push "$IMAGE"

echo "==> Cloud Run"
$TF apply -auto-approve -var "api_image=$IMAGE"

echo "==> Frontend"
# One origin: Firebase rewrites /api/** to Cloud Run, so the API base URL is empty (no CORS).
# Sign-in and the agenda parser stay on AWS: their ids and URL come from the AWS Terraform outputs.
PARSER_URL=$(terraform -chdir=infra output -raw parser_url 2>/dev/null || echo "")
(cd frontend && npm ci && VITE_API_URL="" VITE_PARSER_URL="$PARSER_URL" npm run build)
npx --yes firebase-tools deploy --only hosting --project "$PROJECT_ID"

echo
echo "App: https://$PROJECT_ID.web.app"
echo "API: $($TF output -raw api_url)/api/health"

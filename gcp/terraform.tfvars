# Non-secret settings, reviewed like code. No password lives here: Terraform generates it.
project_id   = "spry-yuna-2026"
region       = "us-central1"
project_name = "spry"

# Public ids (the browser sees them too): terraform -chdir=infra output
cognito_user_pool_id = "eu-central-1_wLilvi79o"
cognito_client_id    = "3untppls7np2f5mdvt6cjs9hrl"

# Optional: act as the Terraform service account instead of your own login
# terraform_service_account = "spry-terraform@spry-yuna-2026.iam.gserviceaccount.com"

# Non-secret settings, reviewed in pull requests like the code. Secrets (google_client_secret)
# and personal values (report_email, budget_email) are variables of the HCP Terraform workspace.

project_name = "spry"
region       = "eu-central-1"

# Public: the browser receives it. The secret half is a workspace variable.
google_client_id = "818472736167-0ai6gaueuekbngjp3nf6bj0oo1jebhir.apps.googleusercontent.com"

# The account has no access to Opus 5.5 (see docs/adr/0006-llm-agenda-parsing.md).
parser_model   = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
bedrock_api    = "runtime"
bedrock_region = "us-east-1"
parser_effort  = "none"

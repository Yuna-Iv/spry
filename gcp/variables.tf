variable "project_id" {
  type        = string
  description = "Google Cloud project ID, e.g. spry-yuna-2026 (permanent, globally unique)."
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Region of Cloud Run, Cloud SQL and Artifact Registry."
}

variable "project_name" {
  type        = string
  default     = "spry"
  description = "Prefix of every resource name and the project_name label."
}

variable "terraform_service_account" {
  type        = string
  default     = ""
  description = "E-mail of the service account Terraform impersonates. Empty: your own gcloud login."
}

variable "api_image" {
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
  description = "Backend image. The default is Google's sample, so the first apply works before any push."
}

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Cloud SQL machine tier (shared core, 0.6 GB)."
}

variable "db_running" {
  type        = bool
  default     = true
  description = "false stops the Cloud SQL instance (activation policy NEVER): compute stops billing, storage does not."
}

variable "cognito_user_pool_id" {
  type        = string
  default     = ""
  description = "Cognito user pool whose ID tokens the API accepts (terraform -chdir=infra output)."
}

variable "cognito_client_id" {
  type        = string
  default     = ""
  description = "Cognito app client the tokens must be issued to."
}

variable "cors_origins" {
  type        = list(string)
  default     = []
  description = "Extra origins allowed to call the API directly. Through the Firebase rewrite there is one origin and no CORS."
}

# Spry's core on Google Cloud: the API on Cloud Run, PostgreSQL on Cloud SQL, the image in
# Artifact Registry, the database URL in Secret Manager. The frontend goes to Firebase Hosting
# (firebase.json in the repository root). Sign-in, reports, the parser and e-mail stay on AWS.
#
# Separate from infra/ on purpose: its own state (workspace spry-gcp), its own provider, so one
# plan can never break both clouds.

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-yuna-iv"

    workspaces {
      name = "spry-gcp"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Credentials: never a JSON key. On a laptop, `gcloud auth application-default login`; with
# terraform_service_account set, Terraform acts as that service account (impersonation) and
# needs only the roles listed in docs/adr/0008-google-cloud.md. In CI: Workload Identity Federation.
provider "google" {
  project                     = var.project_id
  region                      = var.region
  impersonate_service_account = var.terraform_service_account == "" ? null : var.terraform_service_account

  default_labels = {
    project_name = var.project_name
  }
}

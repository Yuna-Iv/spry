# The identity the API runs as. Not the default compute service account, which starts with Editor.
resource "google_service_account" "api" {
  account_id   = "${var.project_name}-api"
  display_name = "Spry API on Cloud Run"
}

# Connect to Cloud SQL through the connector.
resource "google_project_iam_member" "api_cloudsql" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# Read only this one secret.
resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

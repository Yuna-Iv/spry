output "api_url" {
  value       = google_cloud_run_v2_service.api.uri
  description = "Cloud Run URL of the API (try <url>/api/health)."
}

output "image_repository" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
  description = "Where make gcp-deploy pushes the backend image."
}

output "db_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "hosting_urls" {
  value = ["https://${var.project_id}.web.app", "https://${var.project_id}.firebaseapp.com"]
}

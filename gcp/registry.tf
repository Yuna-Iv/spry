# Docker images of the backend: <region>-docker.pkg.dev/<project>/<project_name>/api:<tag>
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.project_name
  format        = "DOCKER"
  description   = "Spry backend images"

  # Keep the 3 newest images; the free tier is 0.5 GB.
  cleanup_policies {
    id     = "keep-3"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
  cleanup_policies {
    id     = "delete-rest"
    action = "DELETE"
    condition {
      tag_state = "ANY"
    }
  }

  depends_on = [google_project_service.apis]
}

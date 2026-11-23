resource "google_cloud_run_v2_service" "api" {
  name                = "${var.project_name}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    scaling {
      min_instance_count = 0 # scales to zero: an idle month costs nothing
      max_instance_count = 2 # 2 instances x (pool 2 + overflow 3) = 10 connections, well under db-f1-micro's limit
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.api_image

      # Cloud Run sends HTTP to this port and also passes it to the container as PORT.
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle = true # request-based billing: CPU only while a request is handled
      }

      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "DB_POOL_SIZE"
        value = "2"
      }
      env {
        name  = "DB_MAX_OVERFLOW"
        value = "3"
      }
      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", concat(["http://localhost:5173"], var.cors_origins))
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.api_database_url,
    google_project_iam_member.api_cloudsql,
  ]
}

# The API checks Cognito ID tokens itself (app/auth.py), so the service is public, like the
# Lambda function URL on AWS. Firebase Hosting's /api/** rewrite also needs this.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

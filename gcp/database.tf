# Cloud SQL for PostgreSQL, the smallest shared-core tier. Unlike Aurora it never pauses:
# it bills by the hour until stopped (db_running = false) or destroyed.
resource "google_sql_database_instance" "main" {
  name                = "${var.project_name}-db"
  database_version    = "POSTGRES_17"
  region              = var.region
  deletion_protection = false # lab: terraform destroy must be able to remove it

  settings {
    # PostgreSQL 16+ defaults to Enterprise Plus, which has no db-f1-micro and costs far more.
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10
    disk_autoresize   = false
    activation_policy = var.db_running ? "ALWAYS" : "NEVER"

    deletion_protection_enabled = false

    backup_configuration {
      enabled = false
    }

    # A public IP with no authorized networks: nobody can connect directly. Cloud Run reaches
    # the instance through the Cloud SQL connector, which checks IAM (roles/cloudsql.client).
    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "app" {
  name     = "meetings"
  instance = google_sql_database_instance.main.name
}

# No special characters: the password goes into a URL and into alembic's config parser.
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  name     = "meetings"
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

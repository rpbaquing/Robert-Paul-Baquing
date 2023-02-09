#### DATABASE ####
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

resource "google_sql_database_instance" "main" {
  name             = "psql-db-${random_id.db_name_suffix.hex}"
  database_version = "POSTGRES_14"
  region           = var.region

  deletion_protection = false

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.main.id
    }
  }

  depends_on = [
      google_service_networking_connection.private_vpc_connection
      ]
}

resource "google_sql_database" "main" {
  name     = "toptaldb"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "main" {
  name     = "admin"
  instance = google_sql_database_instance.main.name
  password = random_password.database.result
}

resource "random_password" "database" {
  length           = 16
  special          = false
}
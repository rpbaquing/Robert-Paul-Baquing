#### CONTAINER REGISTRY ####
resource "google_artifact_registry_repository" "main" {
  location      = var.region
  repository_id = var.name
  description   = "docker repository"
  format        = "DOCKER"
}

resource "google_artifact_registry_repository_iam_member" "gke" {
  project = var.project_id
  location = var.region
  repository = google_artifact_registry_repository.main.name
  role = "roles/artifactregistry.reader"
  member = "serviceAccount:${google_service_account.gke.email}"
}
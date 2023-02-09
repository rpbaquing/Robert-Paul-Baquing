#### COMPUTE ####
resource "google_service_account" "gke" {
  account_id   = "gke-sa-id"
  display_name = "GKE Service Account"
}

resource "google_container_cluster" "main" {
  name     = "${var.name}-cluster"
  location = "${var.region}-a"

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.main.self_link
  subnetwork      = google_compute_subnetwork.main.name
  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.main.secondary_ip_range[1].range_name
    services_secondary_range_name = google_compute_subnetwork.main.secondary_ip_range[0].range_name
  }
}

resource "google_container_node_pool" "main" {
  name       = "${var.name}-node-pool"
  cluster    = google_container_cluster.main.id
  node_count = 1

  node_config {
    machine_type = "n1-standard-2"
    image_type   = "COS_CONTAINERD"
    service_account = google_service_account.gke.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 1
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}
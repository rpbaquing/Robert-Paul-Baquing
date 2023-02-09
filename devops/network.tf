#### NETWORK ####
resource "google_compute_network" "main" {
  name = var.name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = "gke"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.main.id
  secondary_ip_range {
    range_name    = "gke-service"
    ip_cidr_range = "192.168.10.0/24"
  }
  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "192.168.11.0/24"
  }
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_compute_global_address" "ingress" {
  name = "ingress"
}

#### DNS ####
data "google_dns_managed_zone" "main" {
  name = "cloudmade-io"
}

resource "google_dns_record_set" "web" {
  name = "www.${data.google_dns_managed_zone.main.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.main.name

  rrdatas = [google_compute_global_address.ingress.address]
}

resource "google_dns_record_set" "api" {
  name = "api.${data.google_dns_managed_zone.main.dns_name}"
  type = "A"
  ttl  = 300

  managed_zone = data.google_dns_managed_zone.main.name

  rrdatas = [google_compute_global_address.ingress.address]
}
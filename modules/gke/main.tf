# modules/gke/main.tf

data "google_client_config" "default" {}

locals {
  project_id = data.google_client_config.default.project
}

# 1. VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.project_name}-vpc"
  auto_create_subnetworks = false
}

# 2. Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_name}-subnet"
  region        = var.gcp_region
  network       = google_compute_network.vpc.id
  ip_cidr_range = "10.10.0.0/24"
}

# 3. GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_name}-gke"
  location = var.gcp_region

  # Kubernetes version (defaults to 1.31)
  min_master_version = var.cluster_version

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  # Default node pool settings - CRITICAL for quota
  # Even though we remove it, GCP validates quota against the default pool first
  node_config {
    disk_size_gb = 20
    disk_type    = "pd-standard"
    machine_type = "e2-medium"
  }
  
  deletion_protection = false

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}

# 4. Managed Node Pool
resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.project_name}-node-pool"
  location   = var.gcp_region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  # Use same Kubernetes version as cluster
  version = var.cluster_version

  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    
    # Minimize disk size to stay within free/low quota (Default is 100GB)
    disk_size_gb = 20
    disk_type    = "pd-standard" # Use standard HDD instead of SSD

    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    service_account = google_service_account.default.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# 5. Service Account for Nodes
resource "google_service_account" "default" {
  account_id   = "${var.project_name}-gke-sa"
  display_name = "GKE Service Account for ${var.project_name}"
}

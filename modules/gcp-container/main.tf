# modules/gcp-container/main.tf
# Deploys a container to Google Cloud Run (Serverless)

resource "google_cloud_run_v2_service" "default" {
  name     = "${var.project_name}-run"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = var.app_image
      
      ports {
        container_port = 80
      }
    }
  }
}

# Allow public access (unauthenticated)
resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_v2_service.default.name
  location = google_cloud_run_v2_service.default.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}


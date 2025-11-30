# modules/gcp-container/main.tf
# Deploys a container to Google Cloud Run (Serverless)

locals {
  # GCP Cloud Run prefers Docker Hub or GCR/Artifact Registry.
  # Map ECR Public images back to Docker Hub
  image_map = {
    "public.ecr.aws/nginx/nginx:latest"      = "nginx:latest"
    "public.ecr.aws/yeasy/simple-web:latest" = "yeasy/simple-web:latest"
  }

  effective_image = lookup(local.image_map, var.app_image, (
    can(regex("^public\\.ecr\\.aws", var.app_image)) ? "nginx:latest" : var.app_image
  ))
}

resource "google_cloud_run_v2_service" "default" {
  name     = "${var.project_name}-run"
  location = var.gcp_region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    containers {
      image = local.effective_image
      
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


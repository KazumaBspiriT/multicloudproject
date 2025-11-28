resource "aws_apprunner_service" "app" {
  service_name = "${var.project_name}-service"

  source_configuration {
    image_repository {
      image_identifier      = var.app_image
      image_repository_type = "ECR_PUBLIC" # Starts simple with public images

      image_configuration {
        port = "80"
      }
    }
    auto_deployments_enabled = false
  }

  instance_configuration {
    cpu    = "1024" # 1 vCPU
    memory = "2048" # 2 GB
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
    Mode      = "Container"
  }
}


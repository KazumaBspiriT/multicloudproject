variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "gcp_region" {
  type        = string
  description = "GCP region"
}

variable "app_image" {
  type        = string
  description = "Container image to deploy"
}


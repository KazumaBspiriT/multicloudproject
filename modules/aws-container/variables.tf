variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "app_image" {
  description = "The public container image to deploy (e.g., nginx:latest, public.ecr.aws/amazonlinux/amazonlinux:latest)"
  type        = string
}

variable "domain_name" {
  description = "Custom domain name for App Runner service (optional)."
  type        = string
  default     = ""
}

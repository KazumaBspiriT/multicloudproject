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

variable "app_image_aws" {
  description = "Override image URI for AWS (ECR Public/Private). If empty, uses app_image."
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Custom domain name for App Runner service (optional)."
  type        = string
  default     = ""
}

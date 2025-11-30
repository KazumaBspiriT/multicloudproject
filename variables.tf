# variables.tf (Root) - Defines all root-level input variables used by the CI/CD pipeline

variable "project_name" {
  description = "A unique prefix for all resources created."
  type        = string
  default     = "multi-cloud-app"
}

# CHANGED: Now accepts a list of strings for multi-cloud deployment
variable "target_clouds" {
  description = "List of target cloud platforms: aws, azure, gcp."
  type        = list(string)
  default     = ["aws"]
  validation {
    condition = alltrue([
      for c in var.target_clouds : contains(["aws", "azure", "gcp"], c)
    ])
    error_message = "All target_clouds must be one of: aws, azure, or gcp."
  }
}

variable "deployment_mode" {
  description = "The deployment target: 'k8s' for managed clusters, 'container' for App Runner, or 'static' for free-tier object storage."
  type        = string
  default     = "k8s"
  validation {
    condition     = contains(["k8s", "static", "container"], var.deployment_mode)
    error_message = "deployment_mode must be one of: k8s, static, container."
  }
}

variable "app_image" {
  description = "Container image to deploy (Docker Hub URI for GCP/Azure). Example: nginx:latest"
  type        = string
  default     = "nginx:latest"
}

variable "app_image_aws" {
  description = "AWS ECR (Public/Private) image URI. Required for AWS App Runner if not using 'nginx:latest'. Example: public.ecr.aws/nginx/nginx:latest"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Custom domain name for the application (e.g., myapp.com). Leave empty for default/none."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "us-east-2" # Ohio
}

variable "cluster_version" {
  description = "The Kubernetes version to deploy."
  type        = string
  default     = "1.31"
}

variable "static_content_path" {
  description = "Local path to the folder containing the static website (index.html, etc.)."
  type        = string
  default     = "static-app-content"
}

# Add placeholder variables for future Azure/GCP configuration
variable "azure_region" {
  description = "Azure region for deployment."
  type        = string
  default     = "eastus"
}

variable "gcp_region" {
  description = "GCP region for deployment."
  type        = string
  default     = "us-central1"
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = null # Must be provided if using GCP
}

variable "additional_admin_arns" {
  description = "List of IAM ARNs (Users or Roles) to grant admin access to the cluster."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for EKS private subnets. NAT Gateways cost ~$32/month. Set to false to use public subnets (cost-saving, but less secure)."
  type        = bool
  default     = false  # Default to false to save costs
}

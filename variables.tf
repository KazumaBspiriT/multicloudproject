# variables.tf (Root) - Defines all root-level input variables used by the CI/CD pipeline

variable "project_name" {
  description = "A unique prefix for all resources created."
  type        = string
  default     = "multi-cloud-app"
}

variable "target_cloud" {
  description = "The target cloud platform: aws, azure, or gcp."
  type        = string
  default     = "aws"
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.target_cloud)
    error_message = "The target_cloud must be one of: aws, azure, or gcp."
  }
}

variable "deployment_mode" {
  description = "The deployment target: 'k8s' for managed clusters or 'static' for free-tier object storage."
  type        = string
  default     = "k8s"
  validation {
    condition     = contains(["k8s", "static"], var.deployment_mode)
    error_message = "deployment_mode must be one of: k8s, static."
  }
}

variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "us-east-2" # Ohio
}

variable "cluster_version" {
  description = "The Kubernetes version to deploy."
  type        = string
  default     = "1.29"
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

variable "additional_admin_arns" {
  description = "List of IAM ARNs (Users or Roles) to grant admin access to the cluster."
  type        = list(string)
  default     = []
}
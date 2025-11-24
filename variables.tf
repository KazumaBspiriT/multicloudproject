# variables.tf (Root)

# ... (Existing variables remain)

variable "deployment_mode" {
  description = "The deployment target: 'k8s' for managed clusters or 'static' for free-tier object storage."
  type        = string
  default     = "k8s"
  validation {
    condition     = contains(["k8s", "static"], var.deployment_mode)
    error_message = "deployment_mode must be one of: k8s, static."
  }
}

variable "static_content_path" {
  description = "Local path to the folder containing the static website (index.html, etc.)."
  type        = string
  default     = "static-app-content"
}
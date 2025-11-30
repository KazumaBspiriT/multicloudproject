# modules/aws-domain/variables.tf

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "domain_name" {
  description = "Custom domain name"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "Existing ACM certificate ARN (optional, will create if empty)"
  type        = string
  default     = ""
}


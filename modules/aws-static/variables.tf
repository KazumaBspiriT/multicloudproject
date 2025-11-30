variable "project_name" {
  description = "Unique prefix for resources."
  type        = string
}

variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
}

variable "static_content_path" {
  description = "Local path to static files (contains index.html, etc.)."
  type        = string
}

variable "domain_name" {
  description = "Custom domain name for CloudFront distribution (optional)."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain (must be in us-east-1). Leave empty to use default CloudFront certificate."
  type        = string
  default     = ""
}

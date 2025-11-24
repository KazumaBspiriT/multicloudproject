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

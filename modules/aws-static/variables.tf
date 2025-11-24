# modules/aws-static/variables.tf
# Defines input variables required for S3 static website provisioning.

variable "project_name" { 
  type = string 
}

variable "aws_region" { 
  type = string 
}

variable "static_content_path" { 
  type = string 
}
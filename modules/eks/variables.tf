# modules/eks/variables.tf

variable "project_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cluster_version" {
  type = string
}

variable "node_instance_type" {
  description = "Instance type for the EKS worker nodes (e.g., t3.medium)."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "additional_admin_arns" {
  description = "List of IAM ARNs (Users or Roles) to explicitly grant admin access to the cluster"
  type        = list(string)
  default     = []
}

variable "domain_name" {
  description = "Custom domain name for EKS Ingress (optional)."
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets. NAT Gateways cost ~$32/month. Set to false to use public subnets only (cost-saving)."
  type        = bool
  default     = false  # Changed default to false to save costs
}
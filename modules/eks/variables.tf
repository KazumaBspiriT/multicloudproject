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
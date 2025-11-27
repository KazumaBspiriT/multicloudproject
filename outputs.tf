locals {
  eks_enabled = var.target_cloud == "aws" && var.deployment_mode == "k8s" && length(module.eks) > 0
}

output "eks_cluster_name" {
  value       = local.eks_enabled ? module.eks[0].cluster_name : null
  description = "EKS cluster name (null when not deployed)"
}

output "eks_cluster_endpoint" {
  value       = local.eks_enabled ? module.eks[0].cluster_endpoint : null
  description = "EKS API endpoint (null when not deployed)"
}

output "eks_cluster_ca" {
  value       = local.eks_enabled ? module.eks[0].cluster_ca : null
  description = "Cluster CA (base64; null when not deployed)"
}

output "website_endpoint" {
  value       = var.deployment_mode == "static" && var.target_cloud == "aws" ? module.aws_static[0].cloudfront_url : null
  description = "The CloudFront distribution URL"
}

output "website_bucket" {
  value       = var.deployment_mode == "static" && var.target_cloud == "aws" ? module.aws_static[0].bucket_name : null
  description = "The S3 bucket name"
}

output "container_url" {
  value       = var.deployment_mode == "container" && var.target_cloud == "aws" ? module.aws_container[0].service_url : null
  description = "The URL of the App Runner service (Container Mode)"
}

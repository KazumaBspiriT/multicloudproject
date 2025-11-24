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

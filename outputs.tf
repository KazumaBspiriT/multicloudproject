locals {
  eks_enabled        = contains(var.target_clouds, "aws") && var.deployment_mode == "k8s" && length(module.eks) > 0
  gke_enabled        = contains(var.target_clouds, "gcp") && var.deployment_mode == "k8s" && length(module.gke) > 0
  gcp_static_enabled = contains(var.target_clouds, "gcp") && var.deployment_mode == "static" && length(module.gcp_static) > 0
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

output "gke_cluster_name" {
  value = local.gke_enabled ? module.gke[0].cluster_name : null
}

output "gke_cluster_endpoint" {
  value = local.gke_enabled ? module.gke[0].cluster_endpoint : null
}

output "gke_kubeconfig_command" {
  value = local.gke_enabled ? module.gke[0].kubeconfig_raw : null
}

output "website_endpoint" {
  value = coalesce(
    var.deployment_mode == "static" && contains(var.target_clouds, "aws") ? module.aws_static[0].cloudfront_url : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "gcp") ? module.gcp_static[0].website_url : null,
    "N/A"
  )
  description = "The Website URL"
}

output "website_bucket" {
  value = coalesce(
    var.deployment_mode == "static" && contains(var.target_clouds, "aws") ? module.aws_static[0].bucket_name : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "gcp") ? module.gcp_static[0].bucket_name : null,
    "N/A"
  )
  description = "The Storage bucket name"
}

output "container_url" {
  value       = var.deployment_mode == "container" && contains(var.target_clouds, "aws") ? module.aws_container[0].service_url : null
  description = "The URL of the App Runner service (Container Mode)"
}

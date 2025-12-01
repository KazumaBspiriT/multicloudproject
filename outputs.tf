locals {
  eks_enabled        = contains(var.target_clouds, "aws") && var.deployment_mode == "k8s" && length(module.eks) > 0
  gke_enabled        = contains(var.target_clouds, "gcp") && var.deployment_mode == "k8s" && length(module.gke) > 0
  aks_enabled        = contains(var.target_clouds, "azure") && var.deployment_mode == "k8s" && length(module.aks) > 0
  gcp_static_enabled = contains(var.target_clouds, "gcp") && var.deployment_mode == "static" && length(module.gcp_static) > 0
  azure_static_enabled = contains(var.target_clouds, "azure") && var.deployment_mode == "static" && length(module.azure_static) > 0
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

output "eks_vpc_id" {
  value       = local.eks_enabled ? module.eks[0].vpc_id : null
  description = "VPC ID where EKS cluster is deployed (null when not deployed)"
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

output "aks_cluster_name" {
  value = local.aks_enabled ? module.aks[0].cluster_name : null
}

output "aks_cluster_endpoint" {
  value       = local.aks_enabled ? module.aks[0].cluster_endpoint : null
  sensitive   = true
  description = "AKS API endpoint (sensitive, null when not deployed)"
}

output "aks_resource_group_name" {
  value = local.aks_enabled ? module.aks[0].resource_group_name : null
}

output "eks_acm_certificate_arn" {
  description = "ACM certificate ARN for EKS custom domain (if domain_name provided)"
  value       = local.eks_enabled && var.domain_name != "" ? try(module.eks[0].acm_certificate_arn, null) : null
}

output "eks_nameservers" {
  description = "Nameservers for EKS hosted zone (if auto-created)"
  value       = local.eks_enabled && var.domain_name != "" ? try(module.eks[0].nameservers, null) : null
}

output "website_endpoint" {
  value = coalesce(
    var.deployment_mode == "static" && contains(var.target_clouds, "aws") ? module.aws_static[0].cloudfront_url : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "gcp") ? module.gcp_static[0].website_url : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "azure") ? module.azure_static[0].website_url : null,
    "N/A"
  )
  description = "The Website URL"
}

output "website_bucket" {
  value = coalesce(
    var.deployment_mode == "static" && contains(var.target_clouds, "aws") ? module.aws_static[0].bucket_name : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "gcp") ? module.gcp_static[0].bucket_name : null,
    var.deployment_mode == "static" && contains(var.target_clouds, "azure") ? module.azure_static[0].storage_account_name : null,
    "N/A"
  )
  description = "The Storage bucket/account name"
}

output "container_url" {
  value = coalesce(
    var.deployment_mode == "container" && contains(var.target_clouds, "aws") ? module.aws_container[0].service_url : null,
    var.deployment_mode == "container" && contains(var.target_clouds, "gcp") ? module.gcp_container[0].service_url : null,
    var.deployment_mode == "container" && contains(var.target_clouds, "azure") ? module.azure_container[0].service_url : null,
    "N/A"
  )
  description = "The URL of the Container service (App Runner, Cloud Run, or Container Instances)"
}

output "custom_domain_url" {
  description = "Custom domain URL (if domain_name was provided and certificate is validated)"
  value       = var.deployment_mode == "static" && contains(var.target_clouds, "aws") && var.domain_name != "" ? try(module.aws_static[0].custom_domain_url, null) : null
}

output "nameservers" {
  description = "Nameservers for the created hosted zone (update these in your domain registrar if hosted zone was auto-created)"
  value = var.domain_name != "" ? (
    var.deployment_mode == "static" && contains(var.target_clouds, "aws") ? try(module.aws_static[0].nameservers, null) : (
      var.deployment_mode == "container" && contains(var.target_clouds, "aws") ? try(module.aws_container[0].nameservers, null) : (
        var.deployment_mode == "k8s" && contains(var.target_clouds, "aws") ? try(module.eks[0].nameservers, null) : null
      )
    )
  ) : null
}

output "eks_lb_role_arn" {
  description = "IAM Role ARN for the AWS Load Balancer Controller in EKS"
  value       = local.eks_enabled ? try(module.eks[0].lb_role_arn, null) : null
}

# Individual cloud URLs for better visibility
output "aws_container_service_url" {
  description = "AWS App Runner service URL"
  value       = var.deployment_mode == "container" && contains(var.target_clouds, "aws") && length(module.aws_container) > 0 ? module.aws_container[0].service_url : null
}

output "gcp_container_service_url" {
  description = "GCP Cloud Run service URL"
  value       = var.deployment_mode == "container" && contains(var.target_clouds, "gcp") && length(module.gcp_container) > 0 ? module.gcp_container[0].service_url : null
}

output "azure_container_service_url" {
  description = "Azure Container Instance service URL"
  value       = var.deployment_mode == "container" && contains(var.target_clouds, "azure") && length(module.azure_container) > 0 ? module.azure_container[0].service_url : null
}

output "aws_static_cloudfront_url" {
  description = "AWS CloudFront distribution URL"
  value       = var.deployment_mode == "static" && contains(var.target_clouds, "aws") && length(module.aws_static) > 0 ? try(module.aws_static[0].cloudfront_url, null) : null
}

output "gcp_static_website_url" {
  description = "GCP Storage bucket website URL"
  value       = var.deployment_mode == "static" && contains(var.target_clouds, "gcp") && length(module.gcp_static) > 0 ? try(module.gcp_static[0].website_url, null) : null
}

output "azure_static_website_url" {
  description = "Azure Storage account static website URL"
  value       = var.deployment_mode == "static" && contains(var.target_clouds, "azure") && length(module.azure_static) > 0 ? try(module.azure_static[0].website_url, null) : null
}

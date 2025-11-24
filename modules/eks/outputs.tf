output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks_cluster.cluster_endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA data"
  value       = module.eks_cluster.cluster_certificate_authority_data
}

# modules/eks/outputs.tf

output "kubeconfig_raw" {
  description = "The raw kubeconfig content string."
  value       = module.eks_cluster.kubeconfig_raw
  sensitive   = true
}

output "cluster_endpoint" {
  description = "The endpoint URL of the EKS cluster."
  value       = module.eks_cluster.cluster_endpoint
}
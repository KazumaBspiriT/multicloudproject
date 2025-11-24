# outputs.tf (Root)

# This output will ONLY be populated if the 'eks' module is deployed (count > 0)
output "kubeconfig_raw" {
  description = "The raw kubeconfig content for connecting to the cluster."
  value       = var.target_cloud == "aws" ? module.eks[0].kubeconfig_raw : "Not Applicable"
  sensitive   = true # Mark as sensitive since it contains credentials
}

output "cluster_endpoint" {
  description = "The public endpoint URL of the Kubernetes API server."
  value       = var.target_cloud == "aws" ? module.eks[0].cluster_endpoint : "Not Applicable"
}
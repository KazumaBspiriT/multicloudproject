# modules/gke/outputs.tf

# Placeholder outputs for GKE, returning dummy values when deployed.
output "kubeconfig_raw" {
  value     = "Placeholder_GKE_Kubeconfig"
  sensitive = true
}

output "cluster_endpoint" {
  value = "Placeholder_GKE_Endpoint"
}
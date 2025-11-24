# modules/aks/outputs.tf

# Placeholder outputs for AKS, returning dummy values when deployed.
output "kubeconfig_raw" {
  value     = "Placeholder_AKS_Kubeconfig"
  sensitive = true
}

output "cluster_endpoint" {
  value = "Placeholder_AKS_Endpoint"
}
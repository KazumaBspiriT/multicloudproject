# modules/gke/outputs.tf

output "cluster_name" {
  value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
  value = google_container_cluster.primary.endpoint
}

output "cluster_ca_certificate" {
  value = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
}

output "kubeconfig_raw" {
  value     = "Run 'gcloud container clusters get-credentials ${google_container_cluster.primary.name} --region ${var.gcp_region}' to configure kubectl."
  sensitive = false
}

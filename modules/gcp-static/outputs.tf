output "bucket_name" {
  value = google_storage_bucket.site.name
}

output "website_url" {
  description = "URL of the website (HTTP only for bucket website endpoint)"
  value       = "http://${google_storage_bucket.site.name}.storage.googleapis.com/index.html"
}

output "storage_url" {
  description = "Direct HTTPS URL to objects"
  value       = "https://storage.googleapis.com/${google_storage_bucket.site.name}/index.html"
}


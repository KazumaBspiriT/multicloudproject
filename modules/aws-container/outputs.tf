output "service_url" {
  description = "The URL of the App Runner service"
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "service_status" {
  value = aws_apprunner_service.app.status
}


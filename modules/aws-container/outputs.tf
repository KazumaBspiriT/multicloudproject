output "service_url" {
  description = "The URL of the App Runner service"
  value       = "https://${aws_apprunner_service.app.service_url}"
}

output "service_domain" {
  description = "The raw domain of the App Runner service (no protocol)"
  value       = aws_apprunner_service.app.service_url
}

output "service_status" {
  value = aws_apprunner_service.app.status
}

output "custom_domain_url" {
  description = "Custom domain URL (if domain_name was provided)"
  value       = var.domain_name != "" && length(aws_apprunner_custom_domain_association.domain) > 0 ? "https://${var.domain_name}" : null
}

output "nameservers" {
  description = "Nameservers for the created hosted zone (if auto-created)"
  value       = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? aws_route53_zone.domain[0].name_servers : null
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = local.route53_zone_id
}

output "dns_target" {
  description = "App Runner DNS target for custom domain (use this for CNAME or manual DNS configuration)"
  value       = var.domain_name != "" && length(aws_apprunner_custom_domain_association.domain) > 0 ? aws_apprunner_custom_domain_association.domain[0].dns_target : null
}

output "apex_domain_warning" {
  description = "Warning if apex domain is used (CNAME not allowed at apex)"
  value       = var.domain_name != "" && local.is_apex_domain ? "Apex domain detected. CNAME records are not allowed at apex. Configure DNS manually or use a subdomain (e.g., www.${var.domain_name}). DNS target: ${length(aws_apprunner_custom_domain_association.domain) > 0 ? aws_apprunner_custom_domain_association.domain[0].dns_target : "N/A"}" : null
}

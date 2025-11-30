# modules/aws-domain/outputs.tf

output "route53_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = local.route53_zone_id
}

output "certificate_arn" {
  description = "ACM certificate ARN (created or provided)"
  value       = var.acm_certificate_arn != "" ? var.acm_certificate_arn : (var.domain_name != "" && length(aws_acm_certificate_validation.domain) > 0 ? aws_acm_certificate_validation.domain[0].certificate_arn : null)
}

output "nameservers" {
  description = "Nameservers for the hosted zone (if created)"
  value       = var.domain_name != "" && length(aws_acm_certificate_validation.domain) > 0 ? aws_route53_zone.domain[0].name_servers : null
}


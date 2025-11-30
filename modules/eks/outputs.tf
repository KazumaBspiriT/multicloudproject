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

output "vpc_id" {
  description = "VPC ID where EKS cluster is deployed"
  value       = module.vpc.vpc_id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domain (if domain_name provided)"
  value       = var.domain_name != "" && length(aws_acm_certificate_validation.domain) > 0 ? aws_acm_certificate_validation.domain[0].certificate_arn : null
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID (if domain_name provided)"
  value       = local.route53_zone_id
}

output "nameservers" {
  description = "Nameservers for the created hosted zone (if auto-created)"
  value       = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? aws_route53_zone.domain[0].name_servers : null
}

output "lb_role_arn" {
  description = "IAM Role ARN for the AWS Load Balancer Controller"
  value       = module.lb_role.iam_role_arn
}

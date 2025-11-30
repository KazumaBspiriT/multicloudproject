# modules/aws-domain/main.tf
# Shared module for AWS domain automation (used by static, container, k8s)

# Get or create hosted zone
data "aws_route53_zone" "domain" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_zone" "domain" {
  count = var.domain_name != "" && length(data.aws_route53_zone.domain) == 0 ? 1 : 0
  name  = var.domain_name

  tags = {
    Name      = "${var.project_name}-${var.domain_name}"
    ManagedBy = "Terraform"
  }
}

locals {
  route53_zone_id = var.domain_name != "" ? (
    length(data.aws_route53_zone.domain) > 0 ? data.aws_route53_zone.domain[0].zone_id : aws_route53_zone.domain[0].zone_id
  ) : ""
}

# Request ACM certificate (for CloudFront/ALB - must be in us-east-1)
resource "aws_acm_certificate" "domain" {
  count           = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0
  domain_name     = var.domain_name
  validation_method = "DNS"

  provider = aws.us_east_1

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-${var.domain_name}"
    ManagedBy = "Terraform"
  }
}

# Create validation record
resource "aws_route53_record" "cert_validation" {
  count   = var.domain_name != "" && var.acm_certificate_arn == "" && local.route53_zone_id != "" ? 1 : 0
  zone_id = local.route53_zone_id
  name    = aws_acm_certificate.domain[0].domain_validation_options[0].resource_record_name
  type    = aws_acm_certificate.domain[0].domain_validation_options[0].resource_record_type
  records = [aws_acm_certificate.domain[0].domain_validation_options[0].resource_record_value]
  ttl     = 60

  allow_overwrite = true
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "domain" {
  count           = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0
  certificate_arn = aws_acm_certificate.domain[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]

  provider = aws.us_east_1

  timeouts {
    create = "10m"
  }
}

# Outputs
output "route53_zone_id" {
  value = local.route53_zone_id
}

output "certificate_arn" {
  value = var.acm_certificate_arn != "" ? var.acm_certificate_arn : (var.domain_name != "" && length(aws_acm_certificate_validation.domain) > 0 ? aws_acm_certificate_validation.domain[0].certificate_arn : null)
}

output "nameservers" {
  value = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? aws_route53_zone.domain[0].name_servers : null
}


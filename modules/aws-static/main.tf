# modules/aws-static/main.tf
# Private S3 + CloudFront (OAC). HTTPS CDN URL; account-level Block Public Access may remain ON.

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

# Extract apex domain for hosted zone
# If domain is www.example.com, create zone for example.com
# This allows CNAME records for subdomains (www.example.com)
locals {
  # Split domain into parts
  domain_parts = var.domain_name != "" ? split(".", var.domain_name) : []
  # If it's a subdomain (3+ parts), extract apex (last 2 parts)
  # e.g., www.example.com -> example.com
  apex_domain = var.domain_name != "" && length(local.domain_parts) > 2 ? join(".", slice(local.domain_parts, length(local.domain_parts) - 2, length(local.domain_parts))) : var.domain_name
}

# Create hosted zone for apex domain
# This allows CNAME records for subdomains (e.g., www.example.com)
resource "aws_route53_zone" "domain" {
  count = var.domain_name != "" ? 1 : 0
  name  = local.apex_domain

  tags = {
    Name      = "${var.project_name}-${local.apex_domain}"
    ManagedBy = "Terraform"
  }

  # Prevent accidental destruction of zones with other records
  lifecycle {
    prevent_destroy = false
  }
}

# Use the created zone
locals {
  route53_zone_id = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? aws_route53_zone.domain[0].zone_id : ""
}

# Null resource to update nameservers before certificate validation
# This ensures certificate validation can find the validation CNAME record
resource "null_resource" "update_nameservers" {
  count = var.domain_name != "" ? 1 : 0

  # Trigger when hosted zone is created or nameservers change
  triggers = {
    zone_id          = aws_route53_zone.domain[0].zone_id
    zone_nameservers = join(",", aws_route53_zone.domain[0].name_servers)
  }

  # Update nameservers using AWS CLI (Route 53 Domains API)
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Check if domain is Route 53 registered
      R53_REGISTERED=$(aws route53domains list-domains --region us-east-1 --query "Domains[?DomainName=='${local.apex_domain}'].DomainName" --output text 2>/dev/null || echo "")
      
      if [ -n "$R53_REGISTERED" ] && [ "$R53_REGISTERED" = "${local.apex_domain}" ]; then
        echo "Domain ${local.apex_domain} is Route 53 registered"
        
        # Get current nameservers at registrar
        CURRENT_NS=$(aws route53domains get-domain-detail --domain-name "${local.apex_domain}" --region us-east-1 --query 'Nameservers[*].Name' --output text 2>/dev/null | tr '\t' '\n' | sort 2>/dev/null || echo "")
        
        # Get hosted zone nameservers
        ZONE_NS=$(aws route53 get-hosted-zone --id ${aws_route53_zone.domain[0].zone_id} --query 'DelegationSet.NameServers' --output text 2>/dev/null | tr '\t' '\n' | sort 2>/dev/null || echo "")
        
        # Compare (normalize for comparison)
        if [ "$CURRENT_NS" != "$ZONE_NS" ]; then
          echo "Nameservers don't match! Updating..."
          echo "Current: $CURRENT_NS"
          echo "Zone: $ZONE_NS"
          
          # Build JSON array for Route 53 Domains API
          NS_JSON="["
          FIRST=1
          for ns in $(echo "$ZONE_NS" | tr '\n' ' '); do
            if [ $FIRST -eq 1 ]; then
              NS_JSON="$${NS_JSON}{\"Name\":\"$ns\"}"
              FIRST=0
            else
              NS_JSON="$${NS_JSON},{\"Name\":\"$ns\"}"
            fi
          done
          NS_JSON="$${NS_JSON}]"
          
          # Update nameservers
          UPDATE_OUTPUT=$(aws route53domains update-domain-nameservers \
            --domain-name "${local.apex_domain}" \
            --nameservers "$NS_JSON" \
            --region us-east-1 2>&1)
          UPDATE_EXIT=$?
          
          if [ $UPDATE_EXIT -eq 0 ]; then
            echo "Nameservers update request submitted successfully!"
            echo "Waiting for update to complete (this can take 1-5 minutes)..."
            
            # Wait for nameserver update to complete (check status)
            MAX_WAIT=300  # 5 minutes max
            ELAPSED=0
            INTERVAL=10   # Check every 10 seconds
            
            while [ $ELAPSED -lt $MAX_WAIT ]; do
              sleep $INTERVAL
              ELAPSED=$((ELAPSED + INTERVAL))
              
              # Check current nameservers at registrar
              CURRENT_NS_CHECK=$(aws route53domains get-domain-detail --domain-name "${local.apex_domain}" --region us-east-1 --query 'Nameservers[*].Name' --output text 2>/dev/null | tr '\t' '\n' | sort 2>/dev/null || echo "")
              
              # Compare with zone nameservers
              if [ "$CURRENT_NS_CHECK" = "$ZONE_NS" ]; then
                echo "Nameservers updated successfully! ✅ (took $${ELAPSED}s)"
                break
              fi
              
              echo "  Still waiting... ($${ELAPSED}s elapsed)"
            done
            
            if [ "$CURRENT_NS_CHECK" != "$ZONE_NS" ]; then
              echo "⚠️  Nameserver update is still in progress (waited $${ELAPSED}s)"
              echo "   This is normal - update can take 5-10 minutes"
              echo "   Certificate validation will proceed, but may take longer"
            fi
          else
            echo "Failed to update nameservers: $UPDATE_OUTPUT"
            echo "You may need to update manually at your registrar"
          fi
        else
          echo "Nameservers already match! ✅"
        fi
      else
        echo "Domain ${local.apex_domain} is NOT Route 53 registered - skipping nameserver update"
        echo "You must manually update nameservers at your registrar to:"
        aws route53 get-hosted-zone --id ${aws_route53_zone.domain[0].zone_id} --query 'DelegationSet.NameServers' --output text 2>/dev/null | tr '\t' '\n' | sed 's/^/  - /'
      fi
    EOT
  }

  depends_on = [aws_route53_zone.domain]
}

# Request ACM certificate (only if domain_name provided and no ARN given)
resource "aws_acm_certificate" "domain" {
  count             = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  # Certificate must be in us-east-1 for CloudFront
  provider = aws.us_east_1

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-${var.domain_name}"
    ManagedBy = "Terraform"
  }
}

# Note: If acm_certificate_arn is provided, we use it directly in CloudFront
# No need for a data source since we already have the ARN

# Create validation record in Route 53 (automatically)
# IMPORTANT: This depends on nameservers being updated first
# domain_validation_options is a set, so we use tolist() to convert to list
resource "aws_route53_record" "cert_validation" {
  count   = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0
  zone_id = aws_route53_zone.domain[0].zone_id
  name    = tolist(aws_acm_certificate.domain[0].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.domain[0].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.domain[0].domain_validation_options)[0].resource_record_value]
  ttl     = 60

  allow_overwrite = true

  depends_on = [
    aws_route53_zone.domain,
    aws_acm_certificate.domain,
    null_resource.update_nameservers # Ensure nameservers are updated first
  ]
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "domain" {
  count                   = var.domain_name != "" && var.acm_certificate_arn == "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.domain[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]

  provider = aws.us_east_1

  timeouts {
    create = "30m" # Increased timeout to allow for DNS propagation
  }
}

# 1) Private S3 bucket
resource "aws_s3_bucket" "site" {
  bucket        = "${var.project_name}-${var.aws_region}-static-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Project    = var.project_name
    ManagedBy  = "Terraform"
    CostCenter = "FreeTier"
  }
}

resource "aws_s3_bucket_ownership_controls" "own" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "bpa" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2) CloudFront OAC (so CloudFront can read the private S3 origin)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac-${random_string.suffix.result}"
  description                       = "OAC for private S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3) CloudFront distribution (serves index.html over HTTPS)
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Use default certificate if no domain or certificate not ready
    # Otherwise use the validated certificate
    cloudfront_default_certificate = (var.domain_name == "" || (var.acm_certificate_arn == "" && length(aws_acm_certificate_validation.domain) == 0)) ? true : false
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : (var.domain_name != "" && length(aws_acm_certificate_validation.domain) > 0 ? aws_acm_certificate_validation.domain[0].certificate_arn : null)
    ssl_support_method             = (var.domain_name != "" && (var.acm_certificate_arn != "" || length(aws_acm_certificate_validation.domain) > 0)) ? "sni-only" : null
    minimum_protocol_version       = (var.domain_name != "" && (var.acm_certificate_arn != "" || length(aws_acm_certificate_validation.domain) > 0)) ? "TLSv1.2_2021" : null
  }

  # Add custom domain aliases if domain_name is provided and certificate is available
  # IMPORTANT: Only add alias if certificate is validated (prevents CloudFront creation before validation)
  aliases = var.domain_name != "" && (var.acm_certificate_arn != "" || length(aws_acm_certificate_validation.domain) > 0) ? [var.domain_name] : []

  # CRITICAL: CloudFront must wait for certificate validation before creation
  # This ensures alias and certificate are configured from the start
  depends_on = [
    aws_s3_bucket_public_access_block.bpa,
    aws_acm_certificate_validation.domain # Wait for certificate validation
  ]
}

# 5) Upload local site files (needs awscli on the runner/machine)
# MOVED UP: Ensure upload (which creates folders/objects) doesn't race with policy
locals {

  content_dir   = abspath(var.static_content_path)
  content_files = fileset(local.content_dir, "**")
  content_hash = length(local.content_files) == 0 ? "empty" : sha256(join("", [
    for f in local.content_files : filesha256("${local.content_dir}/${f}")
  ]))
}

resource "null_resource" "upload" {
  count = length(local.content_files) == 0 ? 0 : 1

  triggers = {
    content_hash = local.content_hash
  }

  provisioner "local-exec" {
    command = "aws s3 sync ${local.content_dir} s3://${aws_s3_bucket.site.id} --delete"
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.own,
    aws_s3_bucket_public_access_block.bpa,
    # Removed policy dependency to fix race condition
  ]
}

# 4) Bucket policy: allow ONLY this CloudFront distribution to read (not public!)
# MOVED DOWN: Policy applied after potential bucket creation stabilization
data "aws_iam_policy_document" "cf_read" {
  statement {
    sid     = "AllowCloudFrontRead"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.site.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.cf_read.json
  depends_on = [aws_s3_bucket_public_access_block.bpa] # Ensure public access block is set first
}

# Create Route 53 alias record pointing to CloudFront (automatically)
resource "aws_route53_record" "cloudfront_alias" {
  count   = var.domain_name != "" && (var.acm_certificate_arn != "" || length(aws_acm_certificate_validation.domain) > 0) ? 1 : 0
  zone_id = aws_route53_zone.domain[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }

  depends_on = [aws_cloudfront_distribution.cdn]
}

# Output nameservers if hosted zone was created (user needs to update domain registrar)
output "nameservers" {
  value       = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? aws_route53_zone.domain[0].name_servers : null
  description = "Nameservers for the created hosted zone (update these in your domain registrar)"
}

# Outputs
output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

output "custom_domain_url" {
  value       = var.domain_name != "" ? "https://${var.domain_name}" : null
  description = "Custom domain URL (only if domain_name was provided)"
}

output "certificate_arn" {
  value       = var.acm_certificate_arn != "" ? var.acm_certificate_arn : (var.domain_name != "" && length(aws_acm_certificate.domain) > 0 ? aws_acm_certificate.domain[0].arn : null)
  description = "ACM certificate ARN (automatically created or provided)"
}

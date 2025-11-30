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
# If zone already exists, you'll need to import it: terraform import module.aws_container[0].aws_route53_zone.domain[0] ZONE_ID
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
  
  # AWS App Runner requires ECR or ECR Public.
  # Map common Docker Hub images to their ECR Public mirrors
  image_map = {
    "nginx:latest"                 = "public.ecr.aws/nginx/nginx:latest"
    "yeasy/simple-web:latest"      = "public.ecr.aws/nginx/nginx:latest" # Fallback to nginx as yeasy is missing
    "alexwhen/docker-2048:latest"  = "public.ecr.aws/l6m2t8p7/docker-2048:latest"
  }

  effective_image = lookup(local.image_map, var.app_image, (
    can(regex("^public\\.ecr\\.aws", var.app_image)) || can(regex("amazonaws\\.com", var.app_image)) ? var.app_image : "public.ecr.aws/nginx/nginx:latest"
  ))
}

# Request ACM certificate for App Runner
# Note: App Runner handles certificate validation automatically when custom domain is associated
# We don't need to wait for validation - App Runner will validate it
resource "aws_acm_certificate" "domain" {
  count             = var.domain_name != "" ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name      = "${var.project_name}-${var.domain_name}"
    ManagedBy = "Terraform"
  }
}

# Null resource to update nameservers before certificate validation
# This runs a local script to update Route 53 registered domain nameservers
# to match the hosted zone nameservers
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

# Create validation record (domain_validation_options is a set, use tolist)
# IMPORTANT: This depends on nameservers being updated first
resource "aws_route53_record" "cert_validation" {
  count   = var.domain_name != "" ? 1 : 0
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
# Note: We don't specify validation_record_fqdns because Terraform will check
# the certificate status directly. This is more reliable when certificates
# are already validated or validated via Route 53 automatically.
# SKIP certificate validation for App Runner
# App Runner will validate the certificate automatically when custom domain is associated
# We don't need Terraform to wait for validation - App Runner handles it
# resource "aws_acm_certificate_validation" "domain" {
#   count           = var.domain_name != "" ? 1 : 0
#   certificate_arn = aws_acm_certificate.domain[0].arn
#   depends_on = [aws_route53_record.cert_validation]
# }

resource "aws_apprunner_service" "app" {
  service_name = "${var.project_name}-service"

  source_configuration {
    image_repository {
      image_identifier      = local.effective_image
      image_repository_type = "ECR_PUBLIC" # Starts simple with public images
      image_configuration {
        port                          = "80"
        runtime_environment_variables = {}
      }
    }
    auto_deployments_enabled = false
  }

  instance_configuration {
    cpu               = "0.25 vCPU"
    memory            = "0.5 GB"
    instance_role_arn = aws_iam_role.apprunner.arn
  }

  health_check_configuration {
    healthy_threshold   = 1
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 5
  }

  tags = {
    Name      = "${var.project_name}-apprunner"
    ManagedBy = "Terraform"
    Mode      = "Container"
  }
}

# Associate custom domain with App Runner
# Note: App Runner handles certificate validation automatically when domain is associated
# We don't need to wait for certificate validation - App Runner will validate it
# The association will be in "pending_certificate_dns_validation" status until certificate validates
resource "aws_apprunner_custom_domain_association" "domain" {
  count                = var.domain_name != "" ? 1 : 0
  domain_name          = var.domain_name
  service_arn          = aws_apprunner_service.app.arn
  enable_www_subdomain = false

  # App Runner will automatically validate the certificate
  # We just need the certificate to exist and validation record to be created
  depends_on = [
    aws_acm_certificate.domain,
    aws_route53_record.cert_validation,
    null_resource.update_nameservers # Ensure nameservers are synced
  ]
}

# Create CNAME record pointing to App Runner
# Note: Route 53 doesn't allow CNAME at apex (root domain)
# For apex domains (e.g., example.com), we cannot create a CNAME record
# We detect apex by checking if the record name matches the zone name (without trailing dot)
locals {
  # Check if domain_name matches the zone apex
  # Zone is created for apex_domain, so if domain_name == apex_domain, it's apex
  is_apex_domain = var.domain_name != "" && var.domain_name == local.apex_domain
}

# For App Runner, we can only create CNAME for subdomains, not apex domains
# If it's an apex domain, we'll skip the CNAME record creation
# App Runner custom domain association will still work, but DNS must be configured manually
resource "aws_route53_record" "apprunner_cname" {
  # Only check values known at plan time (not resource attributes)
  # Don't check local.route53_zone_id in count (it depends on resource attributes)
  count = var.domain_name != "" && !local.is_apex_domain ? 1 : 0
  # Use zone_id directly from resource (will fail if zone doesn't exist, which is correct)
  zone_id = aws_route53_zone.domain[0].zone_id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 300
  # Use try() to safely get dns_target - if not available, will be empty string (Terraform will handle)
  records = [try(aws_apprunner_custom_domain_association.domain[0].dns_target, "")]

  depends_on = [
    aws_route53_zone.domain,
    aws_apprunner_custom_domain_association.domain
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# For apex domains, App Runner doesn't support CNAME records
# The custom domain association will work, but DNS must be configured manually
# Recommendation: Use a subdomain (e.g., www.example.com) instead

# IAM role for App Runner
resource "aws_iam_role" "apprunner" {
  name = "${var.project_name}-apprunner-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "build.apprunner.amazonaws.com",
            "tasks.apprunner.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = {
    Name      = "${var.project_name}-apprunner-role"
    ManagedBy = "Terraform"
  }
}

# Attach basic execution policy for App Runner
resource "aws_iam_role_policy" "apprunner" {
  name = "${var.project_name}-apprunner-policy"
  role = aws_iam_role.apprunner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

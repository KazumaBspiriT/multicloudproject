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

# Cleanup all records before hosted zone deletion
# This null_resource runs during destroy to delete all records except NS and SOA
resource "null_resource" "cleanup_route53_records" {
  count = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? 1 : 0

  # Store zone ID and domain name for destroy-time cleanup
  triggers = {
    zone_id    = aws_route53_zone.domain[0].zone_id
    domain_name = var.domain_name
  }

  # Delete all records except NS and SOA before hosted zone is destroyed
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e
      # Try to get zone ID from trigger first, fallback to lookup by domain name
      ZONE_ID="${self.triggers.zone_id}"
      DOMAIN_NAME="${self.triggers.domain_name}"
      
      # If zone ID is empty or invalid, try to look it up by domain name
      if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "None" ] || [ "$ZONE_ID" = "placeholder" ]; then
        if [ -n "$DOMAIN_NAME" ]; then
          ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$DOMAIN_NAME" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3 || echo "")
        fi
      fi
      
      if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "None" ]; then
        echo "No zone ID found, skipping cleanup"
        exit 0
      fi
      
      echo "Cleaning up Route 53 records in zone: $ZONE_ID"
      
      # Get all records except NS and SOA
      ALL_RECORDS=$(aws route53 list-resource-record-sets \
        --hosted-zone-id "$ZONE_ID" \
        --max-items 1000 \
        --query "ResourceRecordSets[?Type != 'NS' && Type != 'SOA']" \
        --output json 2>/dev/null || echo "[]")
      
      # Check if jq is available
      if ! command -v jq &> /dev/null; then
        echo "jq not available, attempting cleanup with basic tools..."
        RECORD_COUNT=$(echo "$ALL_RECORDS" | grep -c "Name" || echo "0")
      else
        RECORD_COUNT=$(echo "$ALL_RECORDS" | jq 'length' 2>/dev/null || echo "0")
      fi
      
      if [ "$RECORD_COUNT" = "0" ] || [ -z "$RECORD_COUNT" ]; then
        echo "No records to delete (only NS and SOA remain)"
        exit 0
      fi
      
      echo "Found $RECORD_COUNT record(s) to delete"
      
      if command -v jq &> /dev/null; then
        # Build change batch using jq
        CHANGE_BATCH=$(echo "$ALL_RECORDS" | jq '{
          Changes: [.[] | {
            Action: "DELETE",
            ResourceRecordSet: ({
              Name: .Name,
              Type: .Type,
              TTL: (.TTL // 300),
              ResourceRecords: (.ResourceRecords // []),
              AliasTarget: (.AliasTarget // empty),
              SetIdentifier: (.SetIdentifier // empty),
              Weight: (.Weight // empty),
              Region: (.Region // empty),
              Failover: (.Failover // empty),
              MultiValueAnswer: (.MultiValueAnswer // empty),
              HealthCheckId: (.HealthCheckId // empty),
              TrafficPolicyInstanceId: (.TrafficPolicyInstanceId // empty)
            } | with_entries(select(.value != null and .value != [])))
          }]
        }' 2>/dev/null)
        
        if [ -n "$CHANGE_BATCH" ] && [ "$CHANGE_BATCH" != "{}" ]; then
          TEMP_FILE=$(mktemp)
          echo "$CHANGE_BATCH" > "$TEMP_FILE"
          
          CHANGE_ID=$(aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "file://$TEMP_FILE" \
            --query 'ChangeInfo.Id' \
            --output text 2>/dev/null || echo "")
          
          rm -f "$TEMP_FILE"
          
          if [ -n "$CHANGE_ID" ]; then
            echo "Record deletion initiated (Change ID: $CHANGE_ID)"
            echo "Waiting for deletion to complete..."
            
            # Wait for change to complete (max 2 minutes)
            for i in {1..24}; do
              STATUS=$(aws route53 get-change --id "$CHANGE_ID" --query 'ChangeInfo.Status' --output text 2>/dev/null || echo "PENDING")
              if [ "$STATUS" = "INSYNC" ]; then
                echo "Records deleted successfully"
                break
              fi
              if [ $i -eq 24 ]; then
                echo "Deletion still in progress (waited 2 minutes)"
              else
                sleep 5
              fi
            done
          fi
        fi
      else
        echo "Warning: jq not available, cannot delete records automatically"
        echo "Please delete records manually before destroying hosted zone"
      fi
    EOT
    interpreter = ["/bin/bash", "-c"]
  }

  # No explicit depends_on - we look up zone by name during destroy
  # This ensures cleanup can run even if zone is already marked for destruction
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


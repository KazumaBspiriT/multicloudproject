# modules/eks/main.tf

# 0. Get current caller identity (to automatically grant access to the deployer)
data "aws_caller_identity" "current" {}

# 1. VPC and Networking (A new VPC for EKS is best practice)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.enable_nat_gateway  # Only create NAT gateway if enabled
  enable_dns_hostnames = true

  # Required for EKS nodes in public subnets (when NAT gateway is disabled)
  map_public_ip_on_launch = !var.enable_nat_gateway

  # Tags required for AWS Load Balancer Controller to auto-discover subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}


# 2. EKS Cluster
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" # Use a stable version

  cluster_name    = "${var.project_name}-eks-cluster"
  cluster_version = var.cluster_version

  # Ensure public access so GitHub Actions runner can reach the API server
  cluster_endpoint_public_access = true

  # Enable OIDC for IRSA (IAM Roles for Service Accounts) - Required for ALB Controller
  enable_irsa = true

  vpc_id     = module.vpc.vpc_id
  # Use public subnets if NAT Gateway is disabled (cost-saving), otherwise use private subnets
  subnet_ids = var.enable_nat_gateway ? module.vpc.private_subnets : module.vpc.public_subnets

  # EKS Managed Node Group (using cost-effective instance type for portfolios)
  eks_managed_node_groups = {
    default = {
      name           = "workers" # Shortened to avoid IAM role name length limit (38 chars)
      instance_types = [var.node_instance_type]
      min_size       = 1
      max_size       = 3
      desired_size   = var.node_desired_size
    }
  }

  # Necessary for passing credentials to the cluster later on (kubectl auth)
  enable_cluster_creator_admin_permissions = true

  # Ensure robust access using modern EKS API access entries
  authentication_mode = "API_AND_CONFIG_MAP"

  # Generic: Grant Admin access to any provided additional ARNs
  # Note: current caller is already handled by enable_cluster_creator_admin_permissions = true
  access_entries = {
    for arn in var.additional_admin_arns : arn => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # Set tags for cost tracking
  tags = {
    "Project"    = var.project_name
    "ManagedBy"  = "Terraform"
    "CostCenter" = "Portfolio"
  }
}

# Domain automation for EKS Ingress (ALB)
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

# Cleanup all records before hosted zone deletion
# This null_resource runs during destroy to delete all records except NS and SOA
resource "null_resource" "cleanup_route53_records" {
  count = var.domain_name != "" && length(aws_route53_zone.domain) > 0 ? 1 : 0

  # Store zone ID and domain name for destroy-time cleanup
  triggers = {
    zone_id    = aws_route53_zone.domain[0].zone_id
    domain_name = local.apex_domain
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

  depends_on = [aws_route53_zone.domain]
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

# Request ACM certificate for ALB (must be in same region as cluster, not us-east-1)
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
# CRITICAL: Ansible will wait for this to complete before creating Ingress
resource "aws_acm_certificate_validation" "domain" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.domain[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[0].fqdn]

  timeouts {
    create = "30m" # Increased timeout to allow for DNS propagation
  }
}

# Since Ansible runs locally, we use a local file to store the Kubeconfig temporarily
resource "local_file" "kubeconfig" {
  filename = "${path.root}/kubeconfig.yaml"
  content  = local.kubeconfig
}

# ---------------------------------------------------------
# AWS Load Balancer Controller (Required for ALB Ingress)
# ---------------------------------------------------------

# 1. IAM Role for Service Account
module "lb_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name                              = "${var.project_name}-eks-lb-role"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

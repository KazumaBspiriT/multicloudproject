# main.tf (Root) - Orchestrates the deployment based on variables

terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    # Used to run local commands, e.g., for file uploads
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Backend configuration (filled dynamically by deploy.sh or pipeline)
  backend "s3" {}
}



# -----------------
# AWS Provider Configuration (Uses variable defined in variables.tf)
# -----------------
provider "aws" {
  region = var.aws_region
}

# Additional AWS provider for us-east-1 (required for ACM certificates used by CloudFront)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# -----------------
# GCP Provider Configuration (Uses variable defined in variables.tf)
# -----------------
provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

# -----------------
# Azure Provider Configuration
# -----------------
provider "azurerm" {
  features {}
}

# -----------------
# AWS K8S Module Call (EKS)
# -----------------

module "eks" {
  # ONLY run if 'aws' is in the list of target clouds AND mode is 'k8s'
  count  = contains(var.target_clouds, "aws") && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/eks"

  # Variables passed to the child module (which are defined in root variables.tf)
  project_name          = var.project_name
  aws_region            = var.aws_region
  cluster_version       = var.cluster_version
  additional_admin_arns = var.additional_admin_arns
  domain_name           = var.domain_name
  enable_nat_gateway    = var.enable_nat_gateway
}

module "aws_container" {
  count         = contains(var.target_clouds, "aws") && var.deployment_mode == "container" ? 1 : 0
  source        = "./modules/aws-container"
  project_name  = var.project_name
  aws_region    = var.aws_region
  app_image     = var.app_image
  domain_name   = var.domain_name
}


# -----------------
# AWS Static Module Call (S3)
# -----------------



module "aws_static" {
  count               = contains(var.target_clouds, "aws") && var.deployment_mode == "static" ? 1 : 0
  source              = "./modules/aws-static" # <- dash, not underscore
  project_name        = var.project_name
  aws_region          = var.aws_region
  static_content_path = var.static_content_path
  domain_name         = var.domain_name
  # Leave empty to auto-create certificate, or provide existing ARN
  # If domain_name is provided and this is empty, Terraform will:

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
  # 1. Automatically request ACM certificate
  # 2. Automatically create validation record in Route 53
  # 3. Wait for certificate validation
  # 4. Automatically create alias record pointing to CloudFront
  acm_certificate_arn = ""
}


# -----------------
# Azure Modules
# -----------------

module "aks" {
  count  = contains(var.target_clouds, "azure") && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/aks"

  # ARGUMENTS ADDED HERE to satisfy modules/aks/variables.tf
  project_name    = var.project_name
  azure_region    = var.azure_region
  cluster_version = var.cluster_version
}

module "azure_static" {
  count               = contains(var.target_clouds, "azure") && var.deployment_mode == "static" ? 1 : 0
  source              = "./modules/azure-static"
  project_name        = var.project_name
  azure_region        = var.azure_region
  static_content_path = var.static_content_path
}

module "azure_container" {
  count        = contains(var.target_clouds, "azure") && var.deployment_mode == "container" ? 1 : 0
  source       = "./modules/azure-container"
  project_name = var.project_name
  azure_region = var.azure_region
  app_image    = var.app_image
}

# -----------------
# GCP Modules
# -----------------

module "gcp_static" {
  count               = contains(var.target_clouds, "gcp") && var.deployment_mode == "static" ? 1 : 0
  source              = "./modules/gcp-static"
  project_name        = var.project_name
  gcp_region          = var.gcp_region
  static_content_path = var.static_content_path
}

module "gke" {
  count  = contains(var.target_clouds, "gcp") && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/gke"

  # ARGUMENTS ADDED HERE to satisfy modules/gke/variables.tf
  project_name    = var.project_name
  gcp_region      = var.gcp_region
  cluster_version = var.cluster_version
}

module "gcp_container" {
  count        = contains(var.target_clouds, "gcp") && var.deployment_mode == "container" ? 1 : 0
  source       = "./modules/gcp-container"
  project_name = var.project_name
  gcp_region   = var.gcp_region
  app_image    = var.app_image
}

# -----------------
# Multi-Cloud DNS Integration (Centralized in AWS Route 53)
# -----------------

# 1. Azure Subdomain (azure.yourdomain.com) -> Azure Container Instance IP
resource "aws_route53_record" "azure_subdomain" {
  # Only create if:
  # 1. AWS is enabled (needed for Route 53 Zone)
  # 2. Azure is enabled (needed for IP)
  # 3. Domain is provided
  # 4. Mode is 'container'
  count = contains(var.target_clouds, "aws") && contains(var.target_clouds, "azure") && var.domain_name != "" && var.deployment_mode == "container" ? 1 : 0

  # Get Zone ID from AWS module
  zone_id = module.aws_container[0].route53_zone_id
  
  # Create subdomain 'azure'
  name    = "azure.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [module.azure_container[0].ip_address]
}

# 2. GCP Subdomain (gcp.yourdomain.com) -> Cloud Run
# Note: Cloud Run requires domain verification via Webmaster Central first.
resource "aws_route53_record" "gcp_subdomain" {
  count = contains(var.target_clouds, "aws") && contains(var.target_clouds, "gcp") && var.domain_name != "" && var.deployment_mode == "container" ? 1 : 0

  zone_id = module.aws_container[0].route53_zone_id
  name    = "gcp.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["ghs.googlehosted.com"]
}

# 3. AWS Subdomain (aws.yourdomain.com) -> App Runner (Default Domain)
# This provides a consistent "aws." endpoint alongside azure. and gcp.
resource "aws_route53_record" "aws_subdomain" {
  count = contains(var.target_clouds, "aws") && var.domain_name != "" && var.deployment_mode == "container" ? 1 : 0

  zone_id = module.aws_container[0].route53_zone_id
  name    = "aws.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  # Point to the raw App Runner DNS (e.g. abc.awsapprunner.com)
  records = [module.aws_container[0].service_domain]
}

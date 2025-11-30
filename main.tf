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

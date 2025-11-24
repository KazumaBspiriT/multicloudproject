# main.tf (Root) - Orchestrates the deployment based on variables

terraform {
  required_providers {
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
}

# -----------------
# AWS Provider Configuration (Uses variable defined in variables.tf)
# -----------------
provider "aws" {
  region = var.aws_region
}

# -----------------
# AWS K8S Module Call (EKS)
# -----------------

module "eks" {
  # ONLY run if target is 'aws' AND mode is 'k8s'
  count  = var.target_cloud == "aws" && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/eks" 

  # Variables passed to the child module (which are defined in root variables.tf)
  project_name      = var.project_name
  aws_region        = var.aws_region
  cluster_version   = var.cluster_version
}


# -----------------
# AWS Static Module Call (S3)
# -----------------

module "aws_static" {
  # ONLY run if target is 'aws' AND mode is 'static'
  count  = var.target_cloud == "aws" && var.deployment_mode == "static" ? 1 : 0
  source = "./modules/aws-static"

  # Variables passed to the child module (which are defined in root variables.tf)
  project_name        = var.project_name
  aws_region          = var.aws_region
  static_content_path = var.static_content_path
}

# -----------------
# Placeholder Modules for Azure/GCP (These calls are currently empty)
# -----------------

module "aks" {
  count  = var.target_cloud == "azure" && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/aks" 
}

module "gke" {
  count  = var.target_cloud == "gcp" && var.deployment_mode == "k8s" ? 1 : 0
  source = "./modules/gke" 
}
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

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}


# 2. EKS Cluster
module "eks_cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0" # Use a stable version

  cluster_name    = "${var.project_name}-eks-cluster"
  cluster_version = var.cluster_version

  # Ensure public access so GitHub Actions runner can reach the API server
  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

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

# Since Ansible runs locally, we use a local file to store the Kubeconfig temporarily
resource "local_file" "kubeconfig" {
  filename = "${path.root}/kubeconfig.yaml"
  content  = local.kubeconfig
}

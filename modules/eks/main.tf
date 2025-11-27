# modules/eks/main.tf

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
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

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

  # Set tags for cost tracking
  tags = {
    "Project"    = var.project_name
    "ManagedBy"  = "Terraform"
    "CostCenter" = "Portfolio"
  }
}

# Since Ansible runs locally, we use a local file to store the Kubeconfig temporarily
resource "local_file" "kubeconfig" {
  filename = "${path.module}/kubeconfig_${module.eks_cluster.cluster_name}.yaml"
  content  = local.kubeconfig
}

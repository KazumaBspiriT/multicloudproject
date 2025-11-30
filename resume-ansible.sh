#!/bin/bash
# Quick resume script for Ansible configuration

set -e

echo "=== Resuming Ansible Configuration ==="
echo ""

# Get EKS kubeconfig
echo "1. Updating kubeconfig..."
aws eks update-kubeconfig --region us-east-2 --name multi-cloud-app-eks-cluster --kubeconfig ./kubeconfig.yaml
chmod 600 ./kubeconfig.yaml
echo "✅ Kubeconfig updated"
echo ""

# Get Terraform outputs
echo "2. Getting Terraform outputs..."
ACM_CERT_ARN=$(terraform output -raw eks_acm_certificate_arn 2>/dev/null || echo "")
EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
EKS_VPC_ID=$(terraform output -raw eks_vpc_id 2>/dev/null || echo "")

echo "✅ Variables ready"
echo ""

# Run Ansible
echo "3. Running Ansible playbook..."
ansible-playbook -i ansible/inventory.yml ansible/playbook.yml \
  --extra-vars "deployment_mode=k8s \
                app_image=nginx:latest \
                domain_name=www.sumanthdev2324.com \
                target_clouds=aws \
                acm_certificate_arn=$ACM_CERT_ARN \
                eks_cluster_name=$EKS_CLUSTER_NAME \
                eks_vpc_id=$EKS_VPC_ID \
                aws_region=us-east-2"

echo ""
echo "✅ Ansible configuration complete!"

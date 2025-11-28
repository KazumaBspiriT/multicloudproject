#!/bin/bash
set -e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}--- Multi-Cloud Deployment Trigger ---${NC}"

# 1. Inputs
read -p "Select Action (deploy/destroy) [default: deploy]: " ACTION
ACTION=${ACTION:-deploy}

read -p "Select Target Cloud (aws/azure/gcp) [default: aws]: " CLOUD
CLOUD=${CLOUD:-aws}

read -p "Select Deployment Mode (k8s/static/container) [default: k8s]: " MODE
MODE=${MODE:-k8s}

IMAGE=""
if [[ "$MODE" == "k8s" || "$MODE" == "container" ]]; then
  read -p "Enter Container Image [default: public.ecr.aws/nginx/nginx:latest]: " IMAGE
  IMAGE=${IMAGE:-public.ecr.aws/nginx/nginx:latest}
fi

# 2. Backend Bootstrap
REGION="us-east-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="multicloud-tf-state-${ACCOUNT_ID}"
TABLE_NAME="terraform-locks"

echo -e "\n${BLUE}[0/3] bootstrapping Backend Infrastructure...${NC}"

# Create S3 Bucket if missing
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Creating State Bucket: $BUCKET_NAME..."
  aws s3api create-bucket --bucket "$BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
  aws s3api put-bucket-versioning --bucket "$BUCKET_NAME" --versioning-configuration Status=Enabled
else
  echo "State Bucket $BUCKET_NAME found."
fi

# Create DynamoDB Table if missing
if ! aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo "Creating Lock Table: $TABLE_NAME..."
  aws dynamodb create-table --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --region "$REGION" >/dev/null
else
  echo "Lock Table $TABLE_NAME found."
fi

# 3. Terraform
echo -e "\n${BLUE}[1/3] Initializing Terraform with Remote Backend...${NC}"
terraform init \
  -backend-config="bucket=$BUCKET_NAME" \
  -backend-config="key=global/s3/terraform.tfstate" \
  -backend-config="region=$REGION" \
  -backend-config="dynamodb_table=$TABLE_NAME" \
  -backend-config="encrypt=true"

if [ "$ACTION" == "destroy" ]; then
  echo -e "\n${RED}DESTROYING Infrastructure...${NC}"
  terraform destroy -auto-approve \
    -var="target_cloud=$CLOUD" \
    -var="deployment_mode=$MODE" \
    -var="app_image=$IMAGE"
  echo -e "\n${GREEN}Destroy Complete!${NC}"
  exit 0
fi

echo -e "\n${BLUE}[2/3] Applying Infrastructure...${NC}"
terraform apply -auto-approve \
  -var="target_cloud=$CLOUD" \
  -var="deployment_mode=$MODE" \
  -var="app_image=$IMAGE"

# 4. Post-Processing (Ansible for K8s)
if [[ "$MODE" == "k8s" ]]; then
  echo -e "\n${BLUE}[3/3] Configuring Kubernetes Cluster (Ansible)...${NC}"
  
  # Ensure kubeconfig exists (Terraform should have created it in root)
  export KUBECONFIG="./kubeconfig.yaml"
  
  if [ ! -f "$KUBECONFIG" ]; then
    echo -e "${RED}Error: kubeconfig.yaml not found! Did Terraform fail?${NC}"
    exit 1
  fi

  # Run Ansible
  ansible-playbook -i ansible/inventory.yml ansible/playbook.yml \
    --extra-vars "deployment_mode=$MODE app_image=$IMAGE"
fi

echo -e "\n${GREEN}--------------------------------------"
echo "Deployment Complete!"
echo -e "--------------------------------------${NC}"

# 5. Show Outputs
terraform output

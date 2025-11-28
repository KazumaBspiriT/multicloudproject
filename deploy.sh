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

echo "Enter Target Clouds (comma-separated, e.g. aws,gcp) [default: aws]: "
read -p "> " CLOUDS_INPUT
CLOUDS_INPUT=${CLOUDS_INPUT:-aws}

# Convert comma-separated string to JSON array string for Terraform
# e.g. "aws,gcp" -> '["aws","gcp"]'
IFS=',' read -ra ADDR <<< "$CLOUDS_INPUT"
TF_CLOUDS_LIST="["
for i in "${ADDR[@]}"; do
  TF_CLOUDS_LIST+="\"$i\","
done
TF_CLOUDS_LIST="${TF_CLOUDS_LIST%,}]"

read -p "Select Deployment Mode (k8s/static/container) [default: k8s]: " MODE
MODE=${MODE:-k8s}

IMAGE=""
if [[ "$MODE" == "k8s" || "$MODE" == "container" ]]; then
  read -p "Enter Container Image [default: public.ecr.aws/nginx/nginx:latest]: " IMAGE
  IMAGE=${IMAGE:-public.ecr.aws/nginx/nginx:latest}
fi

# 2. Backend Bootstrap
# Check for GCP Project ID if needed (if 'gcp' is in the list)
if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [[ -z "$PROJECT_ID" ]]; then
     echo -e "${RED}Error: No GCP Project ID found. Run 'gcloud config set project YOUR_PROJECT_ID'${NC}"
     exit 1
  fi
  echo "Using GCP Project: $PROJECT_ID"
fi

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
  
  # Construct TF_VAR arguments
  # Note: We pass the list as a string
  TF_CMD_ARGS="-var=target_clouds=$TF_CLOUDS_LIST -var=deployment_mode=$MODE -var=app_image=$IMAGE"
  if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
    TF_CMD_ARGS="$TF_CMD_ARGS -var=gcp_project_id=$PROJECT_ID"
  fi

  terraform destroy -auto-approve $TF_CMD_ARGS

  echo -e "\n${GREEN}Destroy Complete!${NC}"
  exit 0
fi

echo -e "\n${BLUE}[2/3] Applying Infrastructure...${NC}"
# Construct TF_VAR arguments
TF_CMD_ARGS="-var=target_clouds=$TF_CLOUDS_LIST -var=deployment_mode=$MODE -var=app_image=$IMAGE"
if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
  TF_CMD_ARGS="$TF_CMD_ARGS -var=gcp_project_id=$PROJECT_ID"
fi

terraform apply -auto-approve $TF_CMD_ARGS

# 4. Post-Processing (Ansible for K8s)
if [[ "$MODE" == "k8s" ]]; then
  echo -e "\n${BLUE}[3/3] Configuring Kubernetes Cluster (Ansible)...${NC}"
  
  # Ensure kubeconfig exists (Terraform should have created it in root)
  export KUBECONFIG="./kubeconfig.yaml"

  # For GCP, fetch credentials manually to generate kubeconfig
  if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
     echo "Fetching GKE Credentials..."
     GKE_NAME=$(terraform output -raw gke_cluster_name)
     # Assumes default region us-central1; adjust if variable changes
     gcloud container clusters get-credentials "$GKE_NAME" --region "us-central1"
     # This overwrites AWS kubeconfig if running both simultaneously locally; 
     # A more robust solution would merge them, but for now, GCP takes precedence if selected.
     cp "$HOME/.kube/config" "./kubeconfig.yaml"
  fi
  
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

#!/bin/bash
set -e

# Don't exit on errors in lock detection (non-critical)
set +e

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}[X] $1 is not installed${NC}"
        echo -e "   ${YELLOW}Installation: $2${NC}"
        return 1
    else
        echo -e "${GREEN}[OK] $1 is installed${NC}"
        return 0
    fi
}

# Function to check AWS prerequisites
check_aws() {
    echo -e "\n${BLUE}Checking AWS prerequisites...${NC}"
    local missing=0
    
    if ! check_command "aws" "Install AWS CLI: https://aws.amazon.com/cli/"; then
        missing=1
    fi
    
    if ! check_command "terraform" "Install Terraform: https://www.terraform.io/downloads"; then
        missing=1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${RED}[X] AWS credentials not configured${NC}"
        echo -e "   ${YELLOW}Run: aws configure${NC}"
        missing=1
    else
        echo -e "${GREEN}[OK] AWS credentials configured${NC}"
    fi
    
    return $missing
}

# Function to check GCP prerequisites
check_gcp() {
    echo -e "\n${BLUE}Checking GCP prerequisites...${NC}"
    local missing=0
    
    if ! check_command "gcloud" "Install Google Cloud SDK: https://cloud.google.com/sdk/docs/install"; then
        missing=1
    fi
    
    if ! check_command "terraform" "Install Terraform: https://www.terraform.io/downloads"; then
        missing=1
    fi
    
    # Check GCP authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        echo -e "${RED}[X] GCP not authenticated${NC}"
        echo -e "   ${YELLOW}Run: gcloud auth login${NC}"
        missing=1
    else
        echo -e "${GREEN}[OK] GCP authenticated${NC}"
    fi
    
    # Check GCP project
    local project=$(gcloud config get-value project 2>/dev/null)
    if [ -z "$project" ]; then
        echo -e "${YELLOW}[!] GCP project not set${NC}"
        echo -e "   ${YELLOW}Run: gcloud config set project YOUR_PROJECT_ID${NC}"
        echo -e "   ${YELLOW}Note: You'll be prompted for project ID during deployment${NC}"
    else
        echo -e "${GREEN}[OK] GCP project set: $project${NC}"
    fi
    
    # Check Application Default Credentials
    if ! gcloud auth application-default print-access-token &>/dev/null; then
        echo -e "${YELLOW}[!] Application Default Credentials not set${NC}"
        echo -e "   ${YELLOW}Run: gcloud auth application-default login${NC}"
    else
        echo -e "${GREEN}[OK] Application Default Credentials configured${NC}"
    fi
    
    return $missing
}

# Function to check Azure prerequisites
check_azure() {
    echo -e "\n${BLUE}Checking Azure prerequisites...${NC}"
    local missing=0
    
    if ! check_command "az" "Install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"; then
        missing=1
    fi
    
    if ! check_command "terraform" "Install Terraform: https://www.terraform.io/downloads"; then
        missing=1
    fi
    
    # Check Azure authentication
    if ! az account show &>/dev/null; then
        echo -e "${RED}[X] Azure not authenticated${NC}"
        echo -e "   ${YELLOW}Run: az login${NC}"
        missing=1
    else
        echo -e "${GREEN}[OK] Azure authenticated${NC}"
        local sub=$(az account show --query name -o tsv 2>/dev/null)
        echo -e "   ${GREEN}   Subscription: $sub${NC}"
    fi
    
    return $missing
}

# Function to check common prerequisites
check_common() {
    echo -e "\n${BLUE}Checking common prerequisites...${NC}"
    local missing=0
    
    if ! check_command "terraform" "Install Terraform: https://www.terraform.io/downloads"; then
        missing=1
    fi
    
    if ! check_command "ansible-playbook" "Install Ansible: pip install ansible"; then
        missing=1
    fi
    
    if ! check_command "kubectl" "Install kubectl: https://kubernetes.io/docs/tasks/tools/"; then
        missing=1
    fi
    
    # Check Python and required modules for Ansible
    if ! python3 -c "import kubernetes" &>/dev/null; then
        echo -e "${RED}[X] Python kubernetes module not installed${NC}"
        echo -e "   ${YELLOW}Run: pip install kubernetes${NC}"
        missing=1
    else
        echo -e "${GREEN}[OK] Python kubernetes module installed${NC}"
    fi
    
    # Check Terraform initialization
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}[!] Terraform not initialized${NC}"
        echo -e "   ${YELLOW}Running: terraform init${NC}"
        terraform init
    else
        echo -e "${GREEN}[OK] Terraform initialized${NC}"
    fi
    
    return $missing
}

# Main prerequisite check function
check_prerequisites() {
    echo -e "${BLUE}=========================================="
    echo "Checking Prerequisites"
    echo "==========================================${NC}"
    
    local errors=0
    
    # Check common prerequisites
    if ! check_common; then
        errors=1
    fi
    
    # Check cloud-specific prerequisites based on user input
    # We'll check after getting user input, but show what's needed
    echo -e "\n${YELLOW}Note: Cloud-specific checks will be performed after you select target clouds${NC}"
    
    if [ $errors -eq 1 ]; then
        echo -e "\n${RED}=========================================="
        echo "[X] Prerequisites Check Failed"
        echo "==========================================${NC}"
        echo -e "${YELLOW}Please install missing tools and configure authentication before proceeding.${NC}"
        return 1
    fi
    
    echo -e "\n${GREEN}=========================================="
    echo "[OK] Common Prerequisites Check Passed"
    echo "==========================================${NC}"
    return 0
}

echo -e "${BLUE}--- Multi-Cloud Deployment Trigger ---${NC}"

# Run prerequisite checks
if ! check_prerequisites; then
    exit 1
fi

# 1. Inputs
read -p "Select Action (deploy/destroy) [default: deploy]: " ACTION
ACTION=${ACTION:-deploy}

echo "Enter Target Clouds (comma-separated, e.g. aws,gcp,azure) [default: aws]: "
read -p "> " CLOUDS_INPUT
CLOUDS_INPUT=${CLOUDS_INPUT:-aws}

# Convert comma-separated string to JSON array string for Terraform
IFS=',' read -ra ADDR <<< "$CLOUDS_INPUT"
TF_CLOUDS_LIST="["
for i in "${ADDR[@]}"; do
  # Trim whitespace from each cloud name
  i=$(echo "$i" | xargs)
  TF_CLOUDS_LIST+="\"$i\","
done
TF_CLOUDS_LIST="${TF_CLOUDS_LIST%,}]"
# Ensure no extra whitespace
TF_CLOUDS_LIST=$(echo "$TF_CLOUDS_LIST" | tr -d '\n\r')

# Check cloud-specific prerequisites
echo -e "\n${BLUE}Checking cloud-specific prerequisites for: $CLOUDS_INPUT${NC}"
CLOUD_CHECK_FAILED=0
AWS_CHECKED=0

# Check AWS (either for deployment or S3 backend)
if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
    if ! check_aws; then
        CLOUD_CHECK_FAILED=1
    fi
    AWS_CHECKED=1
fi

# Always check AWS for S3 backend (Terraform state) if not already checked
if [ $AWS_CHECKED -eq 0 ]; then
    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "\n${YELLOW}[!] AWS credentials required for Terraform S3 backend${NC}"
        echo -e "   ${YELLOW}Even if not deploying to AWS, S3 backend requires AWS credentials${NC}"
        if ! check_aws; then
            CLOUD_CHECK_FAILED=1
        fi
    else
        echo -e "\n${GREEN}[OK] AWS credentials available for S3 backend${NC}"
    fi
fi

if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
    if ! check_gcp; then
        CLOUD_CHECK_FAILED=1
    fi
fi

if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
    if ! check_azure; then
        CLOUD_CHECK_FAILED=1
    fi
fi

if [ $CLOUD_CHECK_FAILED -eq 1 ]; then
    echo -e "\n${RED}=========================================="
    echo "[X] Cloud Prerequisites Check Failed"
    echo "==========================================${NC}"
    echo -e "${YELLOW}Please configure missing cloud authentication before proceeding.${NC}"
    exit 1
fi

echo -e "\n${GREEN}[OK] All cloud prerequisites satisfied${NC}\n"

# For destroy, only ask for mode (skip image/domain)
if [ "$ACTION" == "destroy" ]; then
  echo "Select Deployment Mode to destroy for [$CLOUDS_INPUT] (k8s/static/container/all) [default: k8s]: "
  echo "  - 'all' will destroy ALL resources (k8s, static, container) for selected cloud(s)"
  read -p "> " MODE
  MODE=${MODE:-k8s}
  IMAGE=""
  DOMAIN_NAME=""
else
  # For deploy, ask for all details
  echo "Select Deployment Mode for [$CLOUDS_INPUT] (k8s/static/container) [default: k8s]: "
  read -p "> " MODE
  MODE=${MODE:-k8s}

  IMAGE=""
  if [[ "$MODE" == "k8s" || "$MODE" == "container" ]]; then
    # Set default image based on selected cloud
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      # GCP Cloud Run requires Docker Hub image or GCR/Artifact Registry
      DEFAULT_IMAGE="nginx:latest"
    elif [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
      # Use nginx:alpine (smaller, often avoids Docker Hub rate limits better)
      # If you hit rate limits, wait 5-10 minutes and retry, or use Azure Container Registry
      DEFAULT_IMAGE="nginx:alpine"
    else
      # AWS prefers ECR Public or can use Docker Hub
      DEFAULT_IMAGE="public.ecr.aws/nginx/nginx:latest"
    fi
    
    echo "Enter Container Image [default: $DEFAULT_IMAGE]: "
    read -p "> " IMAGE
    IMAGE=${IMAGE:-$DEFAULT_IMAGE}
  fi

# Show custom domain requirements BEFORE prompting (only for AWS)
if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
  echo ""
  echo -e "${YELLOW}[!] IMPORTANT: Custom domain support requires:${NC}"
  echo -e "${YELLOW}   1. Domain registered with AWS Route 53${NC}"
  echo -e "${YELLOW}   2. Nameservers will be automatically updated if domain is Route 53 registered${NC}"
  echo -e "${YELLOW}   3. For external registrars, you must manually update nameservers${NC}"
  echo ""
fi

# Show warning for non-AWS clouds BEFORE prompting
if [[ "$CLOUDS_INPUT" != *"aws"* ]]; then
  echo ""
  echo -e "${YELLOW}[!] WARNING: Custom domain is only supported for AWS deployments${NC}"
  echo -e "${YELLOW}   Domain will be ignored for non-AWS clouds${NC}"
  echo ""
fi

echo "Enter Custom Domain (e.g., myapp.com) [optional]: "
read -p "> " DOMAIN_NAME
DOMAIN_NAME=${DOMAIN_NAME:-""}

# Validate domain input for non-AWS clouds
if [[ -n "$DOMAIN_NAME" ]] && [[ "$CLOUDS_INPUT" != *"aws"* ]]; then
  echo -e "${YELLOW}[!] Domain will be ignored for non-AWS clouds${NC}"
  echo ""
  read -p "Continue anyway? (y/N): " CONTINUE
  if [[ "$CONTINUE" != "y" ]] && [[ "$CONTINUE" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi
fi

# Check static content directory if static mode
if [[ "$MODE" == "static" ]]; then
    STATIC_DIR="static-app-content"
    if [ ! -d "$STATIC_DIR" ]; then
        echo -e "\n${YELLOW}[!] Warning: Static content directory '$STATIC_DIR' not found${NC}"
        echo -e "   ${YELLOW}Creating directory and sample index.html...${NC}"
        mkdir -p "$STATIC_DIR"
        cat > "$STATIC_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Multi-Cloud Static Site</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome to Multi-Cloud Deployment</h1>
    <p>This is a static website deployed across multiple clouds!</p>
</body>
</html>
EOF
        echo -e "${GREEN}[OK] Created sample static content${NC}"
    else
        if [ ! -f "$STATIC_DIR/index.html" ]; then
            echo -e "${YELLOW}[!] Warning: No index.html found in $STATIC_DIR${NC}"
            echo -e "   ${YELLOW}Creating sample index.html...${NC}"
            cat > "$STATIC_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Multi-Cloud Static Site</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <h1>Welcome to Multi-Cloud Deployment</h1>
    <p>This is a static website deployed across multiple clouds!</p>
</body>
</html>
EOF
        fi
        echo -e "${GREEN}[OK] Static content directory found: $STATIC_DIR${NC}"
    fi
fi

# 2. Backend Bootstrap
# AWS credentials are already checked in prerequisites
# S3 backend is used for Terraform state storage
REGION="us-east-2"

# Enable Cloud Run API if deploying GCP container
if [[ "$CLOUDS_INPUT" == *"gcp"* && "$MODE" == "container" ]]; then
  echo "Enabling Cloud Run API..."
  gcloud services enable run.googleapis.com 2>/dev/null || true
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="multicloud-tf-state-${ACCOUNT_ID}"
TABLE_NAME="terraform-locks"

# Check for GCP Project ID if needed (if 'gcp' is in the list)
if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
  PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
  if [[ -z "$PROJECT_ID" ]]; then
     echo -e "${RED}Error: No GCP Project ID found. Run 'gcloud config set project YOUR_PROJECT_ID'${NC}"
     exit 1
  fi
  echo "Using GCP Project: $PROJECT_ID"
fi

# Check for Azure login if needed (if 'azure' is in the list)
if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
  if ! az account show >/dev/null 2>&1; then
     echo -e "${RED}Error: Not logged into Azure. Run 'az login' first.${NC}"
     exit 1
  fi
  AZURE_SUB=$(az account show --query name -o tsv)
  echo "Using Azure Subscription: $AZURE_SUB"
fi

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

# Check for checksum mismatch and fix it (if DynamoDB table exists)
if aws dynamodb describe-table --table-name "$TABLE_NAME" --region "$REGION" >/dev/null 2>&1; then
  echo -e "${BLUE}Checking for state checksum issues...${NC}"
  CHECKSUM_KEY="${BUCKET_NAME}/global/s3/terraform.tfstate-md5"
  CHECKSUM_ITEM=$(aws dynamodb get-item \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --key "{\"LockID\": {\"S\": \"$CHECKSUM_KEY\"}}" \
    --query 'Item' \
    --output json 2>/dev/null)

  if [[ -n "$CHECKSUM_ITEM" ]] && [[ "$CHECKSUM_ITEM" != "null" ]] && [[ "$CHECKSUM_ITEM" != "{}" ]]; then
    echo -e "${YELLOW}⚠️  Found stale checksum entry, removing...${NC}"
    if aws dynamodb delete-item \
      --table-name "$TABLE_NAME" \
      --region "$REGION" \
      --key "{\"LockID\": {\"S\": \"$CHECKSUM_KEY\"}}" \
      2>/dev/null; then
      echo -e "${GREEN}✅ Checksum entry removed${NC}"
    else
      echo -e "${YELLOW}⚠️  Could not remove checksum (continuing anyway)${NC}"
    fi
  else
    echo -e "${GREEN}✅ No checksum issues found${NC}"
  fi
fi

terraform init \
  -backend-config="bucket=$BUCKET_NAME" \
  -backend-config="key=global/s3/terraform.tfstate" \
  -backend-config="region=$REGION" \
  -backend-config="dynamodb_table=$TABLE_NAME" \
  -backend-config="encrypt=true"

# Check for and handle stuck state locks (all operation locks)
# Use subshell to prevent errors from exiting script
(
set +e  # Don't exit on errors in lock check
echo -e "\n${BLUE}Checking for stuck state locks...${NC}"

# Get all locks for this state file (handle errors gracefully)
ALL_LOCKS=$(aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --region "$REGION" \
  --filter-expression "begins_with(LockID, :prefix)" \
  --expression-attribute-values "{\":prefix\":{\"S\":\"$BUCKET_NAME\"}}" \
  --query 'Items[*].{LockID:LockID.S,Info:Info.S}' \
  --output json 2>/dev/null || echo "[]")

# Check if jq is available, if not use simpler method
if command -v jq &> /dev/null; then
  if [[ -n "$ALL_LOCKS" ]] && [[ "$ALL_LOCKS" != "[]" ]] && [[ "$ALL_LOCKS" != "null" ]]; then
    # Filter for operation locks (have Info field with operation type)
    OPERATION_LOCKS=$(echo "$ALL_LOCKS" | jq '[.[] | select(.Info != null and (.Info | contains("OperationType")))]' 2>/dev/null || echo "[]")
    
    if [[ -n "$OPERATION_LOCKS" ]] && [[ "$OPERATION_LOCKS" != "[]" ]] && [[ "$OPERATION_LOCKS" != "null" ]]; then
      LOCK_COUNT=$(echo "$OPERATION_LOCKS" | jq 'length' 2>/dev/null || echo "0")
      
      if [[ "$LOCK_COUNT" -gt 0 ]] && [[ "$LOCK_COUNT" != "0" ]]; then
        echo -e "${YELLOW}⚠️  Found $LOCK_COUNT operation lock(s)${NC}"
        
        # Extract lock IDs
        LOCK_IDS=$(echo "$OPERATION_LOCKS" | jq -r '.[].LockID' 2>/dev/null)
        
        for lock_id in $LOCK_IDS; do
          if [[ -n "$lock_id" ]] && [[ "$lock_id" != "null" ]]; then
            # Extract UUID from lock ID (format: bucket/key-UUID or just UUID)
            LOCK_UUID=$(echo "$lock_id" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
            
            if [[ -n "$LOCK_UUID" ]]; then
              echo -e "${YELLOW}  Attempting to release: $LOCK_UUID${NC}"
              if terraform force-unlock -force "$LOCK_UUID" 2>/dev/null; then
                echo -e "${GREEN}  ✅ Lock released${NC}"
              else
                # Fallback: Delete directly from DynamoDB if force-unlock fails
                echo -e "${YELLOW}  ⚠️  Force-unlock failed, trying direct DynamoDB delete...${NC}"
                if aws dynamodb delete-item \
                  --table-name "$TABLE_NAME" \
                  --region "$REGION" \
                  --key "{\"LockID\": {\"S\": \"$lock_id\"}}" \
                  2>/dev/null; then
                  echo -e "${GREEN}  ✅ Lock deleted from DynamoDB${NC}"
                else
                  echo -e "${YELLOW}  ⚠️  Could not release (may be active operation)${NC}"
                fi
              fi
            fi
          fi
        done
      else
        echo -e "${GREEN}✅ No stuck operation locks found${NC}"
      fi
    else
      echo -e "${GREEN}✅ No stuck operation locks found${NC}"
    fi
  else
    echo -e "${GREEN}✅ No locks found${NC}"
  fi
else
  # Fallback without jq - extract and release locks directly
  LOCK_IDS=$(aws dynamodb scan \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --filter-expression "begins_with(LockID, :prefix) AND attribute_exists(Info)" \
    --expression-attribute-values "{\":prefix\":{\"S\":\"$BUCKET_NAME\"}}" \
    --query 'Items[?Info.S != `null`].LockID.S' \
    --output text 2>/dev/null)
  
  if [[ -n "$LOCK_IDS" ]] && [[ "$LOCK_IDS" != "None" ]]; then
    echo -e "${YELLOW}⚠️  Found potential operation lock(s)${NC}"
    
    for lock_id in $LOCK_IDS; do
      # Extract UUID from lock ID
      LOCK_UUID=$(echo "$lock_id" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
      
      if [[ -n "$LOCK_UUID" ]]; then
        echo -e "${YELLOW}  Attempting to release: $LOCK_UUID${NC}"
        if terraform force-unlock -force "$LOCK_UUID" 2>/dev/null; then
          echo -e "${GREEN}  ✅ Lock released${NC}"
        else
          # Fallback: Delete directly from DynamoDB
          echo -e "${YELLOW}  ⚠️  Force-unlock failed, trying direct DynamoDB delete...${NC}"
          if aws dynamodb delete-item \
            --table-name "$TABLE_NAME" \
            --region "$REGION" \
            --key "{\"LockID\": {\"S\": \"$lock_id\"}}" \
            2>/dev/null; then
            echo -e "${GREEN}  ✅ Lock deleted from DynamoDB${NC}"
          else
            echo -e "${YELLOW}  ⚠️  Could not release (may be active operation)${NC}"
          fi
        fi
      fi
    done
  else
    echo -e "${GREEN}✅ No stuck locks found${NC}"
  fi
fi
) || true  # Always succeed even if lock check fails

if [ "$ACTION" == "destroy" ]; then
  echo -e "\n${RED}=========================================="
  echo "[!] DESTROYING INFRASTRUCTURE [!]"
  echo "==========================================${NC}"
  echo -e "${RED}This will PERMANENTLY DELETE all resources in:${NC}"
  echo "  - Cloud(s): $CLOUDS_INPUT"
  echo "  - Mode: $MODE"
  
  # Show what will be destroyed
  echo -e "\n${BLUE}Resources that will be destroyed:${NC}"
  if [[ "$MODE" == "all" ]]; then
    echo -e "${RED}  [!] ALL RESOURCES for [$CLOUDS_INPUT] [!]${NC}"
    if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
      echo "  - AWS: EKS Cluster, App Runner, S3/CloudFront (ALL modes)"
    fi
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      echo "  - GCP: GKE Cluster, Cloud Run, Storage Bucket (ALL modes)"
    fi
    if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
      echo "  - Azure: AKS Cluster, Container Instances, Storage Account (ALL modes)"
    fi
  elif [[ "$MODE" == "k8s" ]]; then
    if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
      echo "  - AWS: EKS Cluster, VPC, Node Groups"
    fi
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      echo "  - GCP: GKE Cluster, VPC, Node Pools"
    fi
    if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
      echo "  - Azure: AKS Cluster, Resource Group"
    fi
  elif [[ "$MODE" == "container" ]]; then
    if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
      echo "  - AWS: App Runner Service"
    fi
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      echo "  - GCP: Cloud Run Service"
    fi
    if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
      echo "  - Azure: Container Instances, Resource Group"
    fi
  elif [[ "$MODE" == "static" ]]; then
    if [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
      echo "  - AWS: S3 Bucket, CloudFront Distribution"
    fi
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      echo "  - GCP: Cloud Storage Bucket"
    fi
    if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
      echo "  - Azure: Storage Account, Resource Group"
    fi
  fi
  
  # Warn about hosted zones and DNS records
  echo -e "\n${YELLOW}Note about DNS resources:${NC}"
  echo "  - Route 53 Hosted Zones: Will be PRESERVED (not destroyed)"
  echo "  - DNS Records: Will be PRESERVED (not destroyed)"
  echo "  - ACM Certificates: Will be DESTROYED"
  echo "  - To destroy hosted zones, run terraform destroy manually with domain_name"
  
  echo -e "\n${BLUE}Note about VPC cleanup:${NC}"
  echo "  - If VPCs are not deleted automatically, the script will attempt to clean them up"
  echo "  - This includes deleting NAT gateways, internet gateways, subnets, and security groups"
  
  echo -e "\n${RED}This action CANNOT be undone!${NC}"
  read -p "Type 'yes' to confirm destruction: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${GREEN}Destroy cancelled.${NC}"
    exit 0
  fi
  
  echo -e "\n${RED}Starting destruction...${NC}"
  
  # Create temporary tfvars file for list variable to avoid parsing issues
  TEMP_TFVARS=$(mktemp)
  echo "target_clouds = $TF_CLOUDS_LIST" > "$TEMP_TFVARS"
  
  # Pre-destroy cleanup: Delete Kubernetes Ingress to free up ALB/Certificates
  if [[ "$MODE" == "k8s" || "$MODE" == "all" ]]; then
    echo -e "\n${BLUE}Checking for Kubernetes Ingress resources to clean up...${NC}"
    if [ -f "./kubeconfig.yaml" ]; then
      export KUBECONFIG="./kubeconfig.yaml"
      # Delete Ingress to trigger ALB deletion and detach certificate
      if kubectl get ingress -n sample-app portfolio-ingress &> /dev/null; then
        echo -e "${YELLOW}Deleting Ingress to free up ALB and Certificates...${NC}"
        kubectl delete ingress -n sample-app portfolio-ingress --ignore-not-found=true --timeout=60s || true
        echo -e "${GREEN}Ingress deletion initiated. Waiting for ALB cleanup...${NC}"
        # Wait a bit for the controller to process the deletion
        sleep 15
      else
        echo "No Ingress found (or unable to connect to cluster)."
      fi
    else
      echo "No kubeconfig.yaml found. Skipping Ingress cleanup (Terraform will handle it, but might get stuck on Certificate if ALB exists)."
    fi
  fi

  if [[ "$MODE" == "all" ]]; then
    # Destroy all modes sequentially
    for destroy_mode in k8s container static; do
      echo -e "\n${BLUE}Destroying $destroy_mode resources...${NC}"
      TF_CMD_ARGS=(-var-file="$TEMP_TFVARS" -var "deployment_mode=$destroy_mode" -var "app_image=" -var "domain_name=")
      if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
        TF_CMD_ARGS+=(-var "gcp_project_id=$PROJECT_ID")
      fi
      
      # Run destroy with error handling
      if ! terraform destroy -auto-approve "${TF_CMD_ARGS[@]}" 2>&1; then
        echo -e "${YELLOW}  ⚠️  Destroy encountered errors for $destroy_mode mode${NC}"
        echo -e "${YELLOW}  Continuing with cleanup...${NC}"
      fi
    done
  else
    # Destroy specific mode
    TF_CMD_ARGS=(-var-file="$TEMP_TFVARS" -var "deployment_mode=$MODE" -var "app_image=$IMAGE" -var "domain_name=$DOMAIN_NAME")
    if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
      TF_CMD_ARGS+=(-var "gcp_project_id=$PROJECT_ID")
    fi
    if [[ -n "$APP_IMAGE_AWS" ]]; then
      TF_CMD_ARGS+=(-var "app_image_aws=$APP_IMAGE_AWS")
    fi

    # Run destroy with error handling
    if ! terraform destroy -auto-approve "${TF_CMD_ARGS[@]}" 2>&1; then
      echo -e "${YELLOW}⚠️  Destroy encountered errors${NC}"
      echo -e "${YELLOW}Continuing with cleanup of orphaned resources...${NC}"
    fi
  fi
  
  # Clean up temporary file
  rm -f "$TEMP_TFVARS"

  # Cleanup orphaned NAT Gateways first (these are expensive - ~$32/month each!)
  echo -e "\n${RED}⚠️  Checking for orphaned NAT Gateways (these cost ~$32/month each!)...${NC}"
  
  # Get project name from Terraform (default if not available)
  PROJECT_NAME=$(terraform output -raw project_name 2>/dev/null || echo "multi-cloud-app")
  
  # Check for orphaned NAT Gateways in AWS
  if [[ "$CLOUDS_INPUT" == *"aws"* ]] && [[ "$MODE" == "k8s" || "$MODE" == "all" ]]; then
    echo -e "${BLUE}Scanning for orphaned NAT Gateways in region $REGION...${NC}"
    
    # Find all NAT Gateways (not just in VPCs we know about)
    ALL_NAT_GATEWAYS=$(aws ec2 describe-nat-gateways \
      --region "$REGION" \
      --filter "Name=state,Values=available" \
      --query 'NatGateways[*].{NatGatewayId:NatGatewayId,VpcId:VpcId,SubnetId:SubnetId,CreateTime:CreateTime}' \
      --output json 2>/dev/null || echo "[]")
    
    if command -v jq &> /dev/null; then
      NAT_COUNT=$(echo "$ALL_NAT_GATEWAYS" | jq 'length' 2>/dev/null || echo "0")
      
      if [[ "$NAT_COUNT" -gt 0 ]] && [[ "$NAT_COUNT" != "0" ]]; then
        echo -e "${YELLOW}Found $NAT_COUNT NAT Gateway(s) in region $REGION:${NC}"
        echo "$ALL_NAT_GATEWAYS" | jq -r '.[] | "  - \(.NatGatewayId) (VPC: \(.VpcId), Created: \(.CreateTime))"' 2>/dev/null
        
        # Check if any match our project pattern and delete them directly
        echo "$ALL_NAT_GATEWAYS" | jq -r --arg proj "$PROJECT_NAME" '.[] | select(.VpcId != null) | "\(.NatGatewayId)|\(.VpcId)"' 2>/dev/null | while IFS='|' read -r nat_id vpc_id; do
          if [[ -n "$nat_id" ]] && [[ -n "$vpc_id" ]]; then
            VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region "$REGION" --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "")
            if [[ "$VPC_NAME" == *"$PROJECT_NAME"* ]]; then
              echo -e "${YELLOW}  ⚠️  Found orphaned NAT Gateway: $nat_id (VPC: $vpc_id)${NC}"
              echo -e "${YELLOW}     Deleting to prevent charges (~\$32/month)...${NC}"
              if aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$REGION" 2>/dev/null; then
                echo -e "${GREEN}     ✅ NAT Gateway $nat_id deletion initiated${NC}"
                # Wait a bit for deletion to start (but don't wait for full deletion - that can take minutes)
                sleep 2
              else
                echo -e "${YELLOW}     ⚠️  Could not delete NAT Gateway $nat_id (may already be deleting)${NC}"
              fi
            fi
          fi
        done
      else
        echo -e "${GREEN}  ✅ No NAT Gateways found in region $REGION${NC}"
      fi
    else
      echo -e "${YELLOW}  ⚠️  jq not available - skipping detailed NAT Gateway check${NC}"
      echo -e "${YELLOW}   Run: aws ec2 describe-nat-gateways --region $REGION to check manually${NC}"
    fi
  fi
  
  # Cleanup orphaned VPCs (in case destroy failed partway through)
  echo -e "\n${BLUE}Checking for orphaned VPCs...${NC}"
  
  # Clean up AWS VPCs
  if [[ "$CLOUDS_INPUT" == *"aws"* ]] && [[ "$MODE" == "k8s" || "$MODE" == "all" ]]; then
    echo -e "${BLUE}Checking for orphaned AWS VPCs...${NC}"
    VPC_NAME="${PROJECT_NAME}-vpc"
    
    # Find VPCs by name tag
    ORPHANED_VPCS=$(aws ec2 describe-vpcs \
      --region "$REGION" \
      --filters "Name=tag:Name,Values=$VPC_NAME" \
      --query 'Vpcs[*].VpcId' \
      --output text 2>/dev/null || echo "")
    
    if [[ -n "$ORPHANED_VPCS" ]] && [[ "$ORPHANED_VPCS" != "None" ]]; then
      echo -e "${YELLOW}Found orphaned VPC(s): $ORPHANED_VPCS${NC}"
      echo -e "${YELLOW}Attempting to clean up...${NC}"
      
      for vpc_id in $ORPHANED_VPCS; do
        if [[ -n "$vpc_id" ]] && [[ "$vpc_id" != "None" ]]; then
          echo -e "${BLUE}  Cleaning up VPC: $vpc_id${NC}"
          
          # Delete internet gateways
          IGW_IDS=$(aws ec2 describe-internet-gateways \
            --region "$REGION" \
            --filters "Name=attachment.vpc-id,Values=$vpc_id" \
            --query 'InternetGateways[*].InternetGatewayId' \
            --output text 2>/dev/null || echo "")
          
          for igw_id in $IGW_IDS; do
            if [[ -n "$igw_id" ]] && [[ "$igw_id" != "None" ]]; then
              echo "    Detaching and deleting Internet Gateway: $igw_id"
              aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION" 2>/dev/null || true
              aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Delete NAT gateways
          NAT_IDS=$(aws ec2 describe-nat-gateways \
            --region "$REGION" \
            --filter "Name=vpc-id,Values=$vpc_id" \
            --query 'NatGateways[*].NatGatewayId' \
            --output text 2>/dev/null || echo "")
          
          for nat_id in $NAT_IDS; do
            if [[ -n "$nat_id" ]] && [[ "$nat_id" != "None" ]]; then
              echo "    Deleting NAT Gateway: $nat_id"
              aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id" --region "$REGION" 2>/dev/null || true
              # Wait for NAT gateway to be deleted (can take a few minutes)
              echo "    Waiting for NAT Gateway deletion..."
              aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Delete subnets
          SUBNET_IDS=$(aws ec2 describe-subnets \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'Subnets[*].SubnetId' \
            --output text 2>/dev/null || echo "")
          
          for subnet_id in $SUBNET_IDS; do
            if [[ -n "$subnet_id" ]] && [[ "$subnet_id" != "None" ]]; then
              echo "    Deleting Subnet: $subnet_id"
              aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Delete route tables (except main) - disassociate first
          RT_IDS=$(aws ec2 describe-route-tables \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' \
            --output text 2>/dev/null || echo "")
          
          for rt_id in $RT_IDS; do
            if [[ -n "$rt_id" ]] && [[ "$rt_id" != "None" ]]; then
              # Disassociate route table associations first
              ASSOC_IDS=$(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$rt_id" --query 'RouteTables[0].Associations[?Main!=`true`].RouteTableAssociationId' --output text 2>/dev/null || echo "")
              for assoc_id in $ASSOC_IDS; do
                if [[ -n "$assoc_id" ]] && [[ "$assoc_id" != "None" ]]; then
                  echo "    Disassociating Route Table: $assoc_id"
                  aws ec2 disassociate-route-table --association-id "$assoc_id" --region "$REGION" 2>/dev/null || true
                fi
              done
              echo "    Deleting Route Table: $rt_id"
              aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Delete security groups (except default)
          SG_IDS=$(aws ec2 describe-security-groups \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
            --output text 2>/dev/null || echo "")
          
          for sg_id in $SG_IDS; do
            if [[ -n "$sg_id" ]] && [[ "$sg_id" != "None" ]]; then
              echo "    Deleting Security Group: $sg_id"
              aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Delete network ACLs (except default)
          NACL_IDS=$(aws ec2 describe-network-acls \
            --region "$REGION" \
            --filters "Name=vpc-id,Values=$vpc_id" \
            --query 'NetworkAcls[?IsDefault!=`true`].NetworkAclId' \
            --output text 2>/dev/null || echo "")
          
          for nacl_id in $NACL_IDS; do
            if [[ -n "$nacl_id" ]] && [[ "$nacl_id" != "None" ]]; then
              echo "    Deleting Network ACL: $nacl_id"
              aws ec2 delete-network-acl --network-acl-id "$nacl_id" --region "$REGION" 2>/dev/null || true
            fi
          done
          
          # Finally, delete the VPC
          echo "    Deleting VPC: $vpc_id"
          if aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION" 2>/dev/null; then
            echo -e "${GREEN}    ✅ VPC $vpc_id deleted successfully${NC}"
          else
            echo -e "${YELLOW}    ⚠️  Could not delete VPC $vpc_id (may have remaining dependencies)${NC}"
          fi
        fi
      done
    else
      echo -e "${GREEN}  ✅ No orphaned AWS VPCs found${NC}"
    fi
  fi
  
  # Clean up GCP VPCs
  if [[ "$CLOUDS_INPUT" == *"gcp"* ]] && [[ "$MODE" == "k8s" || "$MODE" == "all" ]]; then
    echo -e "${BLUE}Checking for orphaned GCP VPCs...${NC}"
    VPC_NAME="${PROJECT_NAME}-vpc"
    
    # Find VPCs by name
    ORPHANED_VPCS=$(gcloud compute networks list \
      --filter="name=$VPC_NAME" \
      --format="value(name)" \
      --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$ORPHANED_VPCS" ]]; then
      echo -e "${YELLOW}Found orphaned VPC(s): $ORPHANED_VPCS${NC}"
      echo -e "${YELLOW}Attempting to clean up...${NC}"
      
      for vpc_name in $ORPHANED_VPCS; do
        if [[ -n "$vpc_name" ]]; then
          echo -e "${BLUE}  Cleaning up VPC: $vpc_name${NC}"
          
          # Delete subnets first
          SUBNET_NAMES=$(gcloud compute networks subnets list \
            --network="$vpc_name" \
            --format="value(name)" \
            --project="$PROJECT_ID" 2>/dev/null || echo "")
          
          for subnet_name in $SUBNET_NAMES; do
            if [[ -n "$subnet_name" ]]; then
              SUBNET_REGION=$(gcloud compute networks subnets describe "$subnet_name" \
                --format="value(region)" \
                --project="$PROJECT_ID" 2>/dev/null || echo "")
              
              if [[ -n "$SUBNET_REGION" ]]; then
                echo "    Deleting Subnet: $subnet_name in $SUBNET_REGION"
                gcloud compute networks subnets delete "$subnet_name" \
                  --region="$SUBNET_REGION" \
                  --project="$PROJECT_ID" \
                  --quiet 2>/dev/null || true
              fi
            fi
          done
          
          # Delete firewall rules
          FIREWALL_RULES=$(gcloud compute firewall-rules list \
            --filter="network:$vpc_name" \
            --format="value(name)" \
            --project="$PROJECT_ID" 2>/dev/null || echo "")
          
          for rule_name in $FIREWALL_RULES; do
            if [[ -n "$rule_name" ]]; then
              echo "    Deleting Firewall Rule: $rule_name"
              gcloud compute firewall-rules delete "$rule_name" \
                --project="$PROJECT_ID" \
                --quiet 2>/dev/null || true
            fi
          done
          
          # Finally, delete the VPC
          echo "    Deleting VPC: $vpc_name"
          if gcloud compute networks delete "$vpc_name" \
            --project="$PROJECT_ID" \
            --quiet 2>/dev/null; then
            echo -e "${GREEN}    ✅ VPC $vpc_name deleted successfully${NC}"
          else
            echo -e "${YELLOW}    ⚠️  Could not delete VPC $vpc_name (may have remaining dependencies)${NC}"
          fi
        fi
      done
    else
      echo -e "${GREEN}  ✅ No orphaned GCP VPCs found${NC}"
    fi
  fi

  # Cleanup local files
  echo -e "\n${BLUE}Cleaning up local files...${NC}"
  [ -f "./kubeconfig.yaml" ] && rm -f "./kubeconfig.yaml" && echo "  - Removed kubeconfig.yaml"
  [ -f "./terraform.tfstate" ] && echo "  - Note: Remote state in S3 is preserved"
  
  # Clean up any remaining operation locks
  echo -e "\n${BLUE}Cleaning up state locks...${NC}"
  ALL_LOCKS=$(aws dynamodb scan \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --filter-expression "begins_with(LockID, :prefix)" \
    --expression-attribute-values "{\":prefix\":{\"S\":\"$BUCKET_NAME\"}}" \
    --query 'Items[*].{LockID:LockID.S,Info:Info.S}' \
    --output json 2>/dev/null)
  
  if [[ -n "$ALL_LOCKS" ]] && [[ "$ALL_LOCKS" != "[]" ]] && [[ "$ALL_LOCKS" != "null" ]]; then
    OPERATION_LOCKS=$(echo "$ALL_LOCKS" | jq '[.[] | select(.Info != null and (.Info | contains("OperationType")))]' 2>/dev/null)
    
    if [[ -n "$OPERATION_LOCKS" ]] && [[ "$OPERATION_LOCKS" != "[]" ]]; then
      LOCK_IDS=$(echo "$OPERATION_LOCKS" | jq -r '.[].LockID' 2>/dev/null)
      
      for lock_id in $LOCK_IDS; do
        LOCK_UUID=$(echo "$lock_id" | grep -oE '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}' | head -1)
        if [[ -n "$LOCK_UUID" ]]; then
          terraform force-unlock -force "$LOCK_UUID" 2>/dev/null && echo "  - Released lock: $LOCK_UUID" || true
        fi
      done
    fi
  fi

  echo -e "\n${GREEN}=========================================="
  echo "[OK] Destroy Complete!"
  echo "==========================================${NC}"
  exit 0
fi

echo -e "\n${BLUE}[2/3] Applying Infrastructure...${NC}"

# Cost warning for EKS deployments
if [[ "$MODE" == "k8s" ]] && [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
  echo -e "\n${YELLOW}💰 COST WARNING:${NC}"
  echo -e "${YELLOW}   EKS Cluster: ~\$73/month (\$0.10/hour)${NC}"
  echo -e "${YELLOW}   EC2 Instances: Varies by instance type${NC}"
  echo -e "${YELLOW}   NAT Gateway: ~\$32/month if enabled (\$0.045/hour)${NC}"
  echo -e "${YELLOW}   💡 TIP: NAT Gateway is disabled by default to save costs${NC}"
  echo -e "${YELLOW}      Set enable_nat_gateway=true if you need private subnets${NC}"
  echo ""
fi

# Create temporary tfvars file for list variable to avoid parsing issues
TEMP_TFVARS=$(mktemp)
echo "target_clouds = $TF_CLOUDS_LIST" > "$TEMP_TFVARS"

TF_CMD_ARGS=(-var-file="$TEMP_TFVARS" -var "deployment_mode=$MODE" -var "app_image=$IMAGE" -var "domain_name=$DOMAIN_NAME")
if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
  TF_CMD_ARGS+=(-var "gcp_project_id=$PROJECT_ID")
fi
if [[ -n "$APP_IMAGE_AWS" ]]; then
  TF_CMD_ARGS+=(-var "app_image_aws=$APP_IMAGE_AWS")
fi

if ! terraform apply -auto-approve "${TF_CMD_ARGS[@]}"; then
  rm -f "$TEMP_TFVARS"
  echo -e "\n${RED}=========================================="
  echo "[X] Terraform Apply Failed!"
  echo "==========================================${NC}"
  echo -e "${YELLOW}Please check the error messages above.${NC}"
  exit 1
fi

# Clean up temporary file
rm -f "$TEMP_TFVARS"

# 4. Post-Processing (Ansible for K8s)
if [[ "$MODE" == "k8s" ]]; then
  echo -e "\n${BLUE}[3/3] Configuring Kubernetes Cluster (Ansible)...${NC}"
  
  export KUBECONFIG="./kubeconfig.yaml"

  # For GCP, fetch credentials manually to generate kubeconfig
  if [[ "$CLOUDS_INPUT" == *"gcp"* ]]; then
     echo "Fetching GKE Credentials..."
     GKE_NAME=$(terraform output -raw gke_cluster_name)
     
     # Explicitly use our local kubeconfig file for gcloud
     export KUBECONFIG="./kubeconfig.yaml"
     
     # Create a fresh file or append to it
     gcloud container clusters get-credentials "$GKE_NAME" --region "us-central1"
     
     # Ensure permissions are correct
     chmod 600 "./kubeconfig.yaml"
  fi

  # For Azure, fetch credentials manually to generate kubeconfig
  if [[ "$CLOUDS_INPUT" == *"azure"* ]]; then
     echo "Fetching AKS Credentials..."
     AKS_NAME=$(terraform output -raw aks_cluster_name)
     AKS_RG=$(terraform output -raw aks_resource_group_name)
     
     # Check if Azure CLI is logged in
     if ! az account show >/dev/null 2>&1; then
       echo -e "${RED}Error: Not logged into Azure. Run 'az login' first.${NC}"
       exit 1
     fi
     
     # Explicitly use our local kubeconfig file
     export KUBECONFIG="./kubeconfig.yaml"
     
     # Fetch credentials directly to our kubeconfig file
     az aks get-credentials --resource-group "$AKS_RG" --name "$AKS_NAME" --file "./kubeconfig.yaml" --overwrite-existing
     
     # Ensure permissions are correct
     chmod 600 "./kubeconfig.yaml"
  fi
  
  if [ ! -f "$KUBECONFIG" ]; then
    echo -e "${RED}Error: kubeconfig.yaml not found! Did Terraform fail?${NC}"
    exit 1
  fi

  # Pass cloud information to Ansible for cloud-specific Ingress configuration
  # Get certificate ARN from Terraform output (for AWS k8s)
  ACM_CERT_ARN=""
  EKS_CLUSTER_NAME=""
  EKS_VPC_ID=""
  EKS_LB_ROLE_ARN=""
  
  if [[ "$MODE" == "k8s" ]] && [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
    EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
    EKS_VPC_ID=$(terraform output -raw eks_vpc_id 2>/dev/null || echo "")
    EKS_LB_ROLE_ARN=$(terraform output -raw eks_lb_role_arn 2>/dev/null || echo "")
    
    if [[ -n "$DOMAIN_NAME" ]]; then
      ACM_CERT_ARN=$(terraform output -raw eks_acm_certificate_arn 2>/dev/null || echo "")
    fi
  fi

  ansible-playbook -i ansible/inventory.yml ansible/playbook.yml \
    --extra-vars "deployment_mode=$MODE app_image=$IMAGE domain_name=$DOMAIN_NAME target_clouds=$CLOUDS_INPUT acm_certificate_arn=$ACM_CERT_ARN eks_cluster_name=$EKS_CLUSTER_NAME eks_vpc_id=$EKS_VPC_ID aws_region=$REGION eks_lb_role_arn=$EKS_LB_ROLE_ARN"

  # 4a. Automate Route 53 Alias Record Update (for EKS/ALB)
  if [[ "$MODE" == "k8s" ]] && [[ "$CLOUDS_INPUT" == *"aws"* ]] && [[ -n "$DOMAIN_NAME" ]]; then
    echo -e "\n${BLUE}Updating Route 53 DNS for ALB...${NC}"
    
    # Wait for Ingress Hostname
    echo "Waiting for Ingress to be assigned a hostname (max 2 mins)..."
    ALB_HOSTNAME=""
    for i in {1..24}; do
      ALB_HOSTNAME=$(kubectl get ingress -n sample-app portfolio-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
      if [[ -n "$ALB_HOSTNAME" ]]; then
        echo "Found ALB Hostname: $ALB_HOSTNAME"
        break
      fi
      sleep 5
      echo -n "."
    done
    echo ""

    if [[ -n "$ALB_HOSTNAME" ]]; then
      # Get Hosted Zone ID for the domain
      HOSTED_ZONE_ID=$(terraform output -raw route53_zone_id 2>/dev/null || echo "")
      
      if [[ -n "$HOSTED_ZONE_ID" ]]; then
        # Get ALB Canonical Hosted Zone ID (required for Alias record)
        # We can look this up by region or query the ALB
        ALB_NAME=$(echo "$ALB_HOSTNAME" | cut -d'-' -f1-4) # Extract name part loosely
        # Better way: describe-load-balancers filtering by DNS name is tricky without exact name, 
        # but we can query by the name we know Kubernetes generates or just look up the region mapping.
        # For us-east-2, ALB Zone ID is Z3AADJGX6KTTL2.
        # Dynamic lookup:
        ALB_ZONE_ID=$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?DNSName=='$ALB_HOSTNAME'].CanonicalHostedZoneId" --output text 2>/dev/null || echo "")
        
        if [[ -z "$ALB_ZONE_ID" ]]; then
           # Fallback map for common regions
           case "$REGION" in
             us-east-1) ALB_ZONE_ID="Z35SXDOTRQ7X7K" ;;
             us-east-2) ALB_ZONE_ID="Z3AADJGX6KTTL2" ;;
             us-west-1) ALB_ZONE_ID="Z368ELLRRE2KJ0" ;;
             us-west-2) ALB_ZONE_ID="Z1H1FL5HABSF5" ;;
             eu-central-1) ALB_ZONE_ID="Z215JYRZR1TBD5" ;;
             *) echo "Could not determine ALB Zone ID for region $REGION";;
           esac
        fi

        if [[ -n "$ALB_ZONE_ID" ]]; then
          echo "Updating Route 53 Alias record..."
          # Create JSON for batch update
          cat > /tmp/route53_change.json <<EOF
{
  "Comment": "Auto-update Alias record for ALB",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "$DOMAIN_NAME",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$ALB_ZONE_ID",
          "DNSName": "$ALB_HOSTNAME",
          "EvaluateTargetHealth": true
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "www.$DOMAIN_NAME",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "$ALB_ZONE_ID",
          "DNSName": "$ALB_HOSTNAME",
          "EvaluateTargetHealth": true
        }
      }
    }
  ]
}
EOF
          if aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file:///tmp/route53_change.json >/dev/null; then
             echo -e "${GREEN}✅ Route 53 updated successfully!${NC}"
             echo -e "   - $DOMAIN_NAME -> $ALB_HOSTNAME"
             echo -e "   - www.$DOMAIN_NAME -> $ALB_HOSTNAME"
          else
             echo -e "${RED}Failed to update Route 53.${NC}"
          fi
          rm -f /tmp/route53_change.json
        else
          echo -e "${YELLOW}Could not determine ALB Hosted Zone ID. Please create Alias record manually.${NC}"
        fi
      else
        echo -e "${YELLOW}Hosted Zone ID not found in Terraform output.${NC}"
      fi
    else
      echo -e "${YELLOW}ALB Hostname not found (timed out). Please update DNS manually.${NC}"
    fi
  fi
fi

# 5. Show Outputs (only if terraform succeeded)
if terraform output >/dev/null 2>&1; then
  echo -e "\n${GREEN}--------------------------------------"
  echo "Deployment Complete!"
  echo -e "--------------------------------------${NC}"
  terraform output
else
  echo -e "\n${RED}--------------------------------------"
  echo "Deployment Failed!"
  echo -e "--------------------------------------${NC}"
  echo -e "${YELLOW}Terraform state may be corrupted or missing.${NC}"
  echo -e "${YELLOW}If you deleted S3 buckets, you may need to:${NC}"
  echo "  1. Delete the checksum entry from DynamoDB"
  echo "  2. Re-run terraform init"
  exit 1
fi

# 6. Show nameserver update instructions if domain was provided
# Wrap in subshell to prevent errors from exiting script
if [[ -n "$DOMAIN_NAME" ]] && [[ "$CLOUDS_INPUT" == *"aws"* ]]; then
  (
  set +e  # Don't exit on errors in nameserver section
  echo -e "\n${YELLOW}=========================================="
  echo "⚠️  IMPORTANT: Update Domain Nameservers"
  echo "==========================================${NC}"
  
  # Get nameservers from Terraform output or Route 53 directly
  NS_OUTPUT=$(terraform output -json nameservers 2>/dev/null || echo "null")
  EKS_NS=$(terraform output -json eks_nameservers 2>/dev/null || echo "null")
  
  # Initialize variables for nameserver update
  ZONE_ID=""
  NS_LIST=""
  NS_ARRAY_JSON=""
  
  # Get nameservers from terraform output or Route 53
  if [[ "$NS_OUTPUT" != "null" ]] && [[ "$NS_OUTPUT" != "[]" ]] && [[ "$NS_OUTPUT" != "" ]]; then
    echo -e "${BLUE}Route 53 Nameservers for $DOMAIN_NAME:${NC}"
    if command -v jq &> /dev/null; then
      NS_LIST=$(echo "$NS_OUTPUT" | jq -r '.[]' 2>/dev/null | tr '\n' '\t')
      echo "$NS_OUTPUT" | jq -r '.[]' 2>/dev/null
    else
      NS_LIST=$(echo "$NS_OUTPUT" | tr -d '[]"' | tr ',' '\t')
      echo "$NS_OUTPUT"
    fi
    echo ""
    # Get zone ID for update - use apex domain for zone lookup
    # Extract apex domain (www.example.com -> example.com)
    APEX_FOR_ZONE="$DOMAIN_NAME"
    if [[ "$DOMAIN_NAME" =~ ^www\. ]]; then
      APEX_FOR_ZONE="${DOMAIN_NAME#www.}"
    elif [[ "$DOMAIN_NAME" =~ ^[^.]+\. ]]; then
      PARTS=$(echo "$DOMAIN_NAME" | tr '.' '\n' | wc -l)
      if [[ $PARTS -gt 2 ]]; then
        APEX_FOR_ZONE=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')
      fi
    fi
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$APEX_FOR_ZONE" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3)
    # Build JSON array for Route 53 Domains API
    if command -v jq &> /dev/null; then
      NS_ARRAY_JSON=$(echo "$NS_OUTPUT" | jq -r '[.[] | {Name: .}]' 2>/dev/null)
    else
      # Fallback: build JSON manually
      NS_ARRAY_JSON="["
      FIRST=1
      for ns in $(echo "$NS_LIST" | tr '\t' '\n'); do
        if [[ $FIRST -eq 1 ]]; then
          NS_ARRAY_JSON="${NS_ARRAY_JSON}{\"Name\":\"$ns\"}"
          FIRST=0
        else
          NS_ARRAY_JSON="${NS_ARRAY_JSON},{\"Name\":\"$ns\"}"
        fi
      done
      NS_ARRAY_JSON="${NS_ARRAY_JSON}]"
    fi
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "1. Go to your domain registrar (where you bought $DOMAIN_NAME)"
    echo "2. Update nameservers to the values above"
    echo "3. Wait 10-30 minutes for DNS propagation"
    echo "4. Certificate will auto-validate once DNS propagates"
  elif [[ "$EKS_NS" != "null" ]] && [[ "$EKS_NS" != "[]" ]] && [[ "$EKS_NS" != "" ]]; then
    echo -e "${BLUE}Route 53 Nameservers for $DOMAIN_NAME:${NC}"
    if command -v jq &> /dev/null; then
      NS_LIST=$(echo "$EKS_NS" | jq -r '.[]' 2>/dev/null | tr '\n' '\t')
      echo "$EKS_NS" | jq -r '.[]' 2>/dev/null
    else
      NS_LIST=$(echo "$EKS_NS" | tr -d '[]"' | tr ',' '\t')
      echo "$EKS_NS"
    fi
    echo ""
    # Get zone ID for update - use apex domain for zone lookup
    # Extract apex domain (www.example.com -> example.com)
    APEX_FOR_ZONE="$DOMAIN_NAME"
    if [[ "$DOMAIN_NAME" =~ ^www\. ]]; then
      APEX_FOR_ZONE="${DOMAIN_NAME#www.}"
    elif [[ "$DOMAIN_NAME" =~ ^[^.]+\. ]]; then
      PARTS=$(echo "$DOMAIN_NAME" | tr '.' '\n' | wc -l)
      if [[ $PARTS -gt 2 ]]; then
        APEX_FOR_ZONE=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')
      fi
    fi
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$APEX_FOR_ZONE" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3)
    # Build JSON array for Route 53 Domains API
    if command -v jq &> /dev/null; then
      NS_ARRAY_JSON=$(echo "$EKS_NS" | jq -r '[.[] | {Name: .}]' 2>/dev/null)
    else
      # Fallback: build JSON manually
      NS_ARRAY_JSON="["
      FIRST=1
      for ns in $(echo "$NS_LIST" | tr '\t' '\n'); do
        if [[ $FIRST -eq 1 ]]; then
          NS_ARRAY_JSON="${NS_ARRAY_JSON}{\"Name\":\"$ns\"}"
          FIRST=0
        else
          NS_ARRAY_JSON="${NS_ARRAY_JSON},{\"Name\":\"$ns\"}"
        fi
      done
      NS_ARRAY_JSON="${NS_ARRAY_JSON}]"
    fi
    echo -e "${YELLOW}ACTION REQUIRED:${NC}"
    echo "1. Go to your domain registrar (where you bought $DOMAIN_NAME)"
    echo "2. Update nameservers to the values above"
    echo "3. Wait 10-30 minutes for DNS propagation"
    echo "4. Certificate will auto-validate once DNS propagates"
  else
    # Try to get from Route 53 directly - use apex domain for zone lookup
    # Extract apex domain (www.example.com -> example.com)
    APEX_FOR_ZONE="$DOMAIN_NAME"
    if [[ "$DOMAIN_NAME" =~ ^www\. ]]; then
      APEX_FOR_ZONE="${DOMAIN_NAME#www.}"
    elif [[ "$DOMAIN_NAME" =~ ^[^.]+\. ]]; then
      PARTS=$(echo "$DOMAIN_NAME" | tr '.' '\n' | wc -l)
      if [[ $PARTS -gt 2 ]]; then
        APEX_FOR_ZONE=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')
      fi
    fi
    ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$APEX_FOR_ZONE" --query 'HostedZones[0].Id' --output text 2>/dev/null | cut -d'/' -f3)
    if [[ -n "$ZONE_ID" ]]; then
      NS_LIST=$(aws route53 get-hosted-zone --id "$ZONE_ID" --query 'DelegationSet.NameServers' --output text 2>/dev/null)
      if [[ -n "$NS_LIST" ]]; then
        echo -e "${BLUE}Route 53 Nameservers for $DOMAIN_NAME:${NC}"
        echo "$NS_LIST" | tr '\t' '\n'
        echo ""
        # Build JSON array for Route 53 Domains API
        NS_ARRAY_JSON="["
        FIRST=1
        for ns in $(echo "$NS_LIST" | tr '\t' '\n'); do
          if [[ $FIRST -eq 1 ]]; then
            NS_ARRAY_JSON="${NS_ARRAY_JSON}{\"Name\":\"$ns\"}"
            FIRST=0
          else
            NS_ARRAY_JSON="${NS_ARRAY_JSON},{\"Name\":\"$ns\"}"
          fi
        done
        NS_ARRAY_JSON="${NS_ARRAY_JSON}]"
        echo -e "${YELLOW}ACTION REQUIRED:${NC}"
        echo "1. Go to your domain registrar (where you bought $DOMAIN_NAME)"
        echo "2. Update nameservers to the values above"
        echo "3. Wait 10-30 minutes for DNS propagation"
        echo "4. Certificate will auto-validate once DNS propagates"
      fi
    fi
  fi
  
  # Check if domain is Route 53 registered (can auto-update)
  # Note: Route 53 Domains API registers apex domains, not subdomains
  # So if domain is www.example.com, check for example.com
  echo ""
  echo -e "${BLUE}Checking if domain is Route 53 registered...${NC}"
  # Extract apex domain (remove www. or other subdomain prefixes)
  APEX_DOMAIN="$DOMAIN_NAME"
  if [[ "$DOMAIN_NAME" =~ ^www\. ]]; then
    APEX_DOMAIN="${DOMAIN_NAME#www.}"
  elif [[ "$DOMAIN_NAME" =~ ^[^.]+\. ]]; then
    # Check if it's a subdomain (has more than 2 parts)
    PARTS=$(echo "$DOMAIN_NAME" | tr '.' '\n' | wc -l)
    if [[ $PARTS -gt 2 ]]; then
      # Extract apex (last 2 parts: example.com from www.example.com)
      APEX_DOMAIN=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')
    fi
  fi
  R53_REGISTERED=$(aws route53domains list-domains --region us-east-1 --query "Domains[?DomainName=='$APEX_DOMAIN'].DomainName" --output text 2>/dev/null || echo "")
  
  if [[ -n "$R53_REGISTERED" ]] && [[ "$R53_REGISTERED" == "$APEX_DOMAIN" ]]; then
    echo -e "${GREEN}✅ Domain is Route 53 registered!${NC}"
    echo -e "${BLUE}Note: Nameservers are automatically updated during Terraform apply${NC}"
    echo ""
    
    # Just display the nameservers - don't try to update (already done by null_resource)
    if [[ -n "$NS_LIST" ]]; then
      echo -e "${BLUE}Route 53 Hosted Zone Nameservers:${NC}"
      echo "$NS_LIST" | tr '\t' '\n' | sed 's/^/  - /'
      echo ""
      echo -e "${GREEN}✅ Nameservers were automatically synced during deployment${NC}"
      echo "   (Updated by Terraform null_resource if they didn't match)"
    else
      echo -e "${YELLOW}⚠️  Could not retrieve nameservers${NC}"
    fi
    echo ""
  else
    echo -e "${YELLOW}⚠️  Domain is NOT Route 53 registered${NC}"
    echo "   Nameservers must be updated manually at your registrar"
    echo ""
    echo -e "${BLUE}Common Registrars:${NC}"
    echo "  - GoDaddy: https://www.godaddy.com/help/change-nameservers"
    echo "  - Namecheap: https://www.namecheap.com/support/knowledgebase/article.aspx/767/10"
    echo "  - Google Domains: https://support.google.com/domains/answer/3290309"
  fi
  
  echo -e "\n${YELLOW}==========================================${NC}\n"
  ) || true  # Always succeed even if nameserver section fails
fi

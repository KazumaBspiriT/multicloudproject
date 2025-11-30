#!/bin/bash
set -e

BUCKET_NAME="multicloud-tf-state-864981731192"
STATE_KEY="global/s3/terraform.tfstate"
TABLE_NAME="terraform-locks"

echo "=========================================="
echo "Fixing Terraform State Checksum Mismatch"
echo "=========================================="
echo ""

# Option 1: Clear the checksum entry in DynamoDB (safest)
echo "[1/3] Clearing checksum lock entry in DynamoDB..."
LOCK_ID="${BUCKET_NAME}-${STATE_KEY}-md5"

aws dynamodb delete-item \
  --table-name "$TABLE_NAME" \
  --key "{\"LockID\": {\"S\": \"$LOCK_ID\"}}" \
  2>/dev/null && echo "✅ Checksum entry cleared" || echo "⚠️  No checksum entry found (might be OK)"

# Option 2: Try to get any active locks
echo ""
echo "[2/3] Checking for active locks..."
LOCKS=$(aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --filter-expression "begins_with(LockID, :prefix)" \
  --expression-attribute-values "{\":prefix\":{\"S\":\"$BUCKET_NAME\"}}" \
  --query 'Items[*].LockID.S' \
  --output text 2>/dev/null || echo "")

if [ -n "$LOCKS" ]; then
  echo "Found locks: $LOCKS"
  echo "⚠️  You may need to force-unlock if Terraform is stuck"
else
  echo "✅ No active locks found"
fi

# Option 3: Verify state file exists
echo ""
echo "[3/3] Verifying state file in S3..."
if aws s3 ls "s3://${BUCKET_NAME}/${STATE_KEY}" >/dev/null 2>&1; then
  echo "✅ State file exists in S3"
  echo ""
  echo "=========================================="
  echo "✅ Fix Complete!"
  echo "=========================================="
  echo ""
  echo "Try running terraform init again:"
  echo "  terraform init -reconfigure"
  echo ""
else
  echo "⚠️  State file not found in S3"
  echo "This might be a new deployment"
fi


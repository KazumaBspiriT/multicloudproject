#!/bin/bash
# Helper script to unlock Terraform state

BUCKET_NAME="multicloud-tf-state-864981731192"
TABLE_NAME="terraform-locks"
REGION="us-east-2"

echo "=========================================="
echo "Terraform State Lock Cleanup"
echo "=========================================="
echo ""

# Get all locks
echo "Checking for locks..."
LOCKS=$(aws dynamodb scan \
  --table-name "$TABLE_NAME" \
  --region "$REGION" \
  --filter-expression "begins_with(LockID, :prefix)" \
  --expression-attribute-values "{\":prefix\":{\"S\":\"$BUCKET_NAME\"}}" \
  --query 'Items[*].{LockID:LockID.S,Info:Info.S}' \
  --output json 2>/dev/null)

if [[ -z "$LOCKS" ]] || [[ "$LOCKS" == "[]" ]]; then
  echo "✅ No locks found"
  exit 0
fi

echo "Found locks:"
echo "$LOCKS" | jq -r '.[] | "  - \(.LockID) (\(.Info))"' 2>/dev/null || echo "$LOCKS"

echo ""
read -p "Release all locks? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
  echo "Cancelled"
  exit 0
fi

# Extract lock IDs and unlock
LOCK_IDS=$(echo "$LOCKS" | jq -r '.[].LockID' 2>/dev/null)

for lock_id in $LOCK_IDS; do
  # Extract UUID (last part)
  LOCK_UUID=$(echo "$lock_id" | awk -F'/' '{print $NF}' | awk '{print $1}')
  if [[ -n "$LOCK_UUID" ]]; then
    echo "Releasing lock: $LOCK_UUID"
    terraform force-unlock -force "$LOCK_UUID" 2>/dev/null && \
      echo "  ✅ Released" || \
      echo "  ❌ Failed (may need manual cleanup)"
  fi
done

echo ""
echo "✅ Done!"


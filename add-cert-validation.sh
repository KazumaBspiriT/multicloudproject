#!/bin/bash

CERT_ARN="arn:aws:acm:us-east-1:864981731192:certificate/f4a33100-8e9c-43b8-98e4-76e8db9675f0"
DOMAIN="sumanthdev2324.com"

echo "=========================================="
echo "Adding ACM Certificate Validation Record"
echo "=========================================="

# Get validation record
VALIDATION=$(aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output json)

VALIDATION_NAME=$(echo $VALIDATION | jq -r '.Name')
VALIDATION_VALUE=$(echo $VALIDATION | jq -r '.Value')

echo "Validation Record:"
echo "  Name: $VALIDATION_NAME"
echo "  Type: CNAME"
echo "  Value: $VALIDATION_VALUE"
echo ""

# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$DOMAIN.'].Id" --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$ZONE_ID" ]; then
    echo "ERROR: No hosted zone found for $DOMAIN"
    echo "Please create a hosted zone first in Route 53 console"
    exit 1
fi

echo "Found hosted zone: $ZONE_ID"
echo ""

# Add validation record
echo "Adding validation record to Route 53..."
CHANGE_BATCH=$(cat <<JSON
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$VALIDATION_NAME",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$VALIDATION_VALUE"}]
    }
  }]
}
JSON
)

CHANGE_ID=$(aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch "$CHANGE_BATCH" \
  --query 'ChangeInfo.Id' --output text | cut -d'/' -f3)

echo "=========================================="
echo "Validation record added!"
echo "Change ID: $CHANGE_ID"
echo ""
echo "Next steps:"
echo "1. Wait 5-30 minutes for certificate validation"
echo "2. Check status:"
echo "   aws acm describe-certificate --certificate-arn $CERT_ARN --region us-east-1 --query 'Certificate.Status'"
echo "3. When status is 'ISSUED', update main.tf and redeploy"
echo "=========================================="


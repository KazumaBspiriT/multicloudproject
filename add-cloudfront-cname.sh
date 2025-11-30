#!/bin/bash

DOMAIN="sumanthdev2324.com"
CLOUDFRONT_DOMAIN="d1ra8yxqww0vfq.cloudfront.net"

echo "=========================================="
echo "Adding CNAME Record for Custom Domain"
echo "=========================================="

# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$DOMAIN.'].Id" --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$ZONE_ID" ]; then
    echo "ERROR: No hosted zone found for $DOMAIN"
    exit 1
fi

echo "Hosted Zone ID: $ZONE_ID"
echo "Adding CNAME: $DOMAIN -> $CLOUDFRONT_DOMAIN"
echo ""

# Add CNAME record
CHANGE_BATCH=$(cat <<JSON
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$DOMAIN",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$CLOUDFRONT_DOMAIN"}]
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
echo "✅ CNAME record added!"
echo "Change ID: $CHANGE_ID"
echo ""
echo "Next steps:"
echo "1. Wait 15-20 minutes for CloudFront deployment"
echo "2. Wait 5-60 minutes for DNS propagation"
echo "3. Test: https://$DOMAIN"
echo ""
echo "Check DNS: dig $DOMAIN CNAME"
echo "=========================================="


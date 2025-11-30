#!/bin/bash

DOMAIN="sumanthdev2324.com"
CLOUDFRONT_DOMAIN="d1ra8yxqww0vfq.cloudfront.net"

echo "=========================================="
echo "Adding Alias Record for Custom Domain"
echo "=========================================="

# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='$DOMAIN.'].Id" --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$ZONE_ID" ]; then
    echo "ERROR: No hosted zone found for $DOMAIN"
    exit 1
fi

# Get CloudFront distribution ID
echo "Finding CloudFront distribution..."
CF_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Aliases.Items, '$DOMAIN') || contains(Aliases.Items, 'www.$DOMAIN')].Id" \
  --output text | head -1)

if [ -z "$CF_ID" ]; then
    # Try to find by domain name in comment or other way
    CF_ID=$(aws cloudfront list-distributions \
      --query "DistributionList.Items[?DomainName=='$CLOUDFRONT_DOMAIN'].Id" \
      --output text | head -1)
fi

if [ -z "$CF_ID" ]; then
    echo "ERROR: Could not find CloudFront distribution"
    echo "Please get the distribution ID manually from AWS Console"
    exit 1
fi

echo "CloudFront Distribution ID: $CF_ID"
echo "Hosted Zone ID: $ZONE_ID"
echo "Adding Alias: $DOMAIN -> CloudFront"
echo ""

# Get CloudFront hosted zone ID (always Z2FDTNDATAQYW2 for CloudFront)
CLOUDFRONT_HOSTED_ZONE_ID="Z2FDTNDATAQYW2"

# Add A record with Alias target
CHANGE_BATCH=$(cat <<JSON
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$DOMAIN",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "$CLOUDFRONT_HOSTED_ZONE_ID",
        "DNSName": "$CLOUDFRONT_DOMAIN",
        "EvaluateTargetHealth": false
      }
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
echo "✅ Alias record added!"
echo "Change ID: $CHANGE_ID"
echo ""
echo "Next steps:"
echo "1. Wait 15-20 minutes for CloudFront deployment"
echo "2. Wait 5-60 minutes for DNS propagation"
echo "3. Test: https://$DOMAIN"
echo ""
echo "Check DNS: dig $DOMAIN"
echo "=========================================="


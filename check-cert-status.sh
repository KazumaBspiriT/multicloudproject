#!/bin/bash

CERT_ARN="arn:aws:acm:us-east-1:864981731192:certificate/f4a33100-8e9c-43b8-98e4-76e8db9675f0"

echo "Checking certificate status..."
echo ""

STATUS=$(aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.Status' \
  --output text)

VALIDATION_STATUS=$(aws acm describe-certificate \
  --certificate-arn $CERT_ARN \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ValidationStatus' \
  --output text)

echo "Certificate Status: $STATUS"
echo "Validation Status: $VALIDATION_STATUS"
echo ""

if [ "$STATUS" == "ISSUED" ]; then
    echo "✅ Certificate is ISSUED! Ready to deploy!"
    echo ""
    echo "You can now run:"
    echo "  ./deploy.sh"
    echo "  # Target: aws"
    echo "  # Mode: static"
    echo "  # Domain: sumanthdev2324.com"
elif [ "$STATUS" == "PENDING_VALIDATION" ]; then
    echo "⏳ Still pending validation..."
    echo "This is normal - AWS checks every few minutes"
    echo "Usually takes 5-30 minutes after adding validation record"
    echo ""
    echo "Check again in 5-10 minutes:"
    echo "  ./check-cert-status.sh"
else
    echo "Status: $STATUS"
    echo "Check AWS Console for details"
fi


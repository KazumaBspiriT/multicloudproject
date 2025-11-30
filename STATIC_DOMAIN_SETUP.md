# Custom Domain Setup for Static Content (AWS S3 + CloudFront)

## Overview
You can use your custom domain `sumanthdev2324.com` with AWS static content deployment.

## Step-by-Step Setup

### Step 1: Deploy Static Content
```bash
./deploy.sh
# Target Clouds: aws
# Deployment Mode: static
# Custom Domain: sumanthdev2324.com
```

### Step 2: Request ACM Certificate
ACM certificates for CloudFront **must** be in `us-east-1` region:

```bash
# Request certificate
aws acm request-certificate \
  --domain-name sumanthdev2324.com \
  --validation-method DNS \
  --region us-east-1

# This will return a Certificate ARN - save it!
# Example: arn:aws:acm:us-east-1:123456789012:certificate/abc123...
```

### Step 3: Validate Certificate
The certificate will need DNS validation:

```bash
# Get validation records
aws acm describe-certificate \
  --certificate-arn <CERTIFICATE_ARN> \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord' \
  --output json

# Add the CNAME record to your Route 53 hosted zone
# The output will show Name and Value for the validation record
```

### Step 4: Update CloudFront Distribution
Once certificate is validated, update the Terraform configuration:

**Option A: Update Terraform variable (Recommended)**
```bash
# Edit main.tf, find module "aws_static" and update:
acm_certificate_arn = "arn:aws:acm:us-east-1:YOUR_ACCOUNT:certificate/YOUR_CERT_ID"

# Then apply:
terraform apply -auto-approve
```

**Option B: Manual update via AWS Console**
1. Go to CloudFront Console
2. Select your distribution
3. Edit → General Settings
4. Add `sumanthdev2324.com` to Alternate Domain Names (CNAMEs)
5. Select your ACM certificate
6. Save

### Step 5: Add CNAME Record in Route 53
```bash
# Get CloudFront domain name from Terraform output
terraform output cloudfront_url

# Add CNAME record in Route 53:
# Type: CNAME
# Name: sumanthdev2324.com (or @)
# Value: <CloudFront domain from output>
# TTL: 300
```

Or use AWS CLI:
```bash
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='sumanthdev2324.com.'].Id" --output text | cut -d'/' -f3)
CF_DOMAIN=$(terraform output -raw cloudfront_url | sed 's|https://||' | sed 's|/||')

aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"sumanthdev2324.com\",
        \"Type\": \"CNAME\",
        \"TTL\": 300,
        \"ResourceRecords\": [{\"Value\": \"$CF_DOMAIN\"}]
      }
    }]
  }"
```

### Step 6: Wait and Test
- Wait 5-60 minutes for DNS propagation
- Wait for CloudFront distribution to deploy (15-20 minutes)
- Test: `curl https://sumanthdev2324.com`

## Quick Reference Commands

```bash
# Check certificate status
aws acm describe-certificate \
  --certificate-arn <ARN> \
  --region us-east-1 \
  --query 'Certificate.Status'

# Check CloudFront distribution status
aws cloudfront get-distribution \
  --id <DISTRIBUTION_ID> \
  --query 'Distribution.Status'

# Test DNS
dig sumanthdev2324.com
curl -I https://sumanthdev2324.com
```

## Notes

- **ACM Certificate must be in us-east-1** for CloudFront
- CloudFront distribution updates take 15-20 minutes
- DNS propagation can take 5-60 minutes
- Certificate validation can take 5-30 minutes
- Total setup time: ~30-60 minutes

## Troubleshooting

**Certificate not validating:**
- Check DNS validation record is in Route 53
- Wait 5-10 minutes after adding validation record

**CloudFront not serving custom domain:**
- Verify certificate is in `Issued` status
- Check CNAME record points to CloudFront domain
- Wait for distribution deployment to complete

**HTTPS not working:**
- Ensure ACM certificate is attached to CloudFront
- Check certificate is in `us-east-1` region
- Verify CNAME record is correct


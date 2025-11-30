# Custom Domain Setup Guide

## Overview
This project supports custom domains with HTTPS for all deployment modes across AWS, GCP, and Azure.

## Prerequisites
1. **Domain Name**: You must own a domain (e.g., `example.com`, `myapp.com`)
2. **DNS Access**: Ability to modify DNS records for your domain
3. **Domain Verification**: Some providers require domain verification

## Setup by Cloud Provider

### AWS (EKS, Static, Container)

#### For Kubernetes (EKS):
1. Deploy with domain name: `./deploy.sh` → Enter your domain
2. Wait for LoadBalancer IP from Ingress
3. Point your domain's A record to the LoadBalancer IP
4. For HTTPS, use AWS Certificate Manager (ACM) - see below

#### For Static (S3 + CloudFront):
1. Deploy with domain name
2. The script will create CloudFront distribution
3. You need to:
   - Request ACM certificate in `us-east-1` region
   - Add CNAME record: `yourdomain.com` → CloudFront domain
   - Update CloudFront to use your certificate

#### For Container (App Runner):
- App Runner supports custom domains natively
- Configure in AWS Console after deployment

### GCP (GKE, Static, Container)

#### For Kubernetes (GKE):
1. Deploy with domain name
2. GKE automatically provisions managed SSL certificate
3. Wait for Ingress IP (may take 5-10 minutes)
4. Point your domain's A record to the Ingress IP
5. SSL certificate will be provisioned automatically (takes 10-60 minutes)

#### For Static (GCS):
- Use Cloud Load Balancer with custom domain
- Requires manual setup in GCP Console

#### For Container (Cloud Run):
- Cloud Run supports custom domains natively
- Configure in GCP Console: Cloud Run → Manage Custom Domains

### Azure (AKS, Static, Container)

#### For Kubernetes (AKS):
1. Deploy with domain name
2. Install NGINX Ingress Controller (if not already installed)
3. Create Ingress with your domain
4. Point your domain's A record to the Ingress IP
5. For HTTPS, use Azure Key Vault or Let's Encrypt

#### For Static (Storage Account):
- Use Azure CDN with custom domain
- Requires manual setup in Azure Portal

#### For Container (Container Instances):
- Use Application Gateway with custom domain
- Requires manual setup

## DNS Configuration

### A Record (for LoadBalancer IPs)
```
Type: A
Name: @ (or subdomain like www)
Value: <LoadBalancer_IP>
TTL: 300
```

### CNAME Record (for CloudFront/CDN)
```
Type: CNAME
Name: @ (or subdomain)
Value: <CDN_Domain>
TTL: 300
```

## SSL Certificate Setup

### AWS (ACM)
1. Request certificate in `us-east-1` region
2. Validate domain via DNS or email
3. Update CloudFront distribution to use certificate

### GCP (Managed Certificates)
- Automatically provisioned for GKE Ingress
- Takes 10-60 minutes to provision
- Check status: `kubectl describe managedcertificate portfolio-cert -n sample-app`

### Azure
- Use Azure Key Vault certificates
- Or use Let's Encrypt with cert-manager

## Verification Steps

1. **Check DNS Propagation**:
   ```bash
   dig yourdomain.com
   nslookup yourdomain.com
   ```

2. **Check SSL Certificate**:
   ```bash
   openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
   ```

3. **Test HTTPS**:
   ```bash
   curl -I https://yourdomain.com
   ```

## Troubleshooting

### DNS Not Resolving
- Wait 5-60 minutes for DNS propagation
- Verify DNS records are correct
- Check TTL values

### SSL Certificate Not Provisioned
- **GCP**: Wait up to 60 minutes, verify DNS is correct
- **AWS**: Verify certificate is in `us-east-1`, domain validated
- **Azure**: Check certificate status in Key Vault

### Ingress Not Getting IP
- Wait 5-10 minutes for LoadBalancer provisioning
- Check Ingress status: `kubectl get ingress -n sample-app`
- Verify Ingress controller is installed

## Quick Start Example

```bash
# 1. Deploy with custom domain
./deploy.sh
# Enter domain: myapp.com

# 2. Get the IP/hostname from output
# Example: "Point DNS to IP: 34.123.45.67"

# 3. Add DNS A record
# myapp.com → 34.123.45.67

# 4. Wait for SSL (GCP: 10-60 min, AWS: depends on ACM)

# 5. Access: https://myapp.com
```


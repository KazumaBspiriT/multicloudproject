# Multi-Cloud Deployment Project

Deploy containerized applications across AWS, Azure, and GCP using Terraform and Ansible. Supports three deployment modes: Kubernetes (EKS/GKE), Container Services (App Runner/Cloud Run/ACI), and Static Websites (S3/Storage/CloudFront).

## ⚡ Quick Start

### Local Deployment
```bash
# 1. Install prerequisites (see Prerequisites section below)
# 2. Configure cloud credentials (AWS, GCP, Azure)
# 3. For static mode: Add your HTML files to static-app-content/ folder (see Static Content Preparation section)
# 4. Run deployment script
./deploy.sh
```

### GitHub Actions Pipeline
1. **Set up secrets** (see [GitHub Actions Setup](#-github-actions-setup))
2. Go to **Actions** → **Multi-Cloud Deployment Pipeline** → **Run workflow**
3. Fill in inputs and run

**Required Secrets:**
- `AWS_ACCESS_KEY_ID` & `AWS_SECRET_ACCESS_KEY` (always required)
- `GCP_SA_KEY` (for GCP deployments)
- `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` (for Azure deployments)

## 🚀 Features

- **Multi-Cloud Support**: Deploy to AWS, Azure, and GCP simultaneously
- **Three Deployment Modes**:
  - **Kubernetes (k8s)**: EKS (AWS) and GKE (GCP)
  - **Container**: App Runner (AWS), Cloud Run (GCP), Container Instances (Azure)
  - **Static**: S3 + CloudFront (AWS), Storage Buckets (GCP/Azure)
- **Custom Domain Support**: Automatic DNS configuration with SSL certificates
- **Cost Optimization**: NAT Gateway disabled by default (~$32/month savings)
- **Automated Image Mirroring**: Auto-mirrors Docker Hub images to private registries (ECR/ACR)

## 📋 Prerequisites

### Local Deployment

#### Common Requirements
- **Terraform** >= 1.0: [Installation Guide](https://www.terraform.io/downloads)
- **Ansible** >= 2.9: `pip install ansible`
- **kubectl**: [Installation Guide](https://kubernetes.io/docs/tasks/tools/)
- **Python 3** with modules: `pip install kubernetes openshift jmespath`
- **Docker** (optional, for containerized deployment): [Installation Guide](https://docs.docker.com/get-docker/)

#### Cloud-Specific Requirements

**AWS** (Required for S3 backend, even if not deploying to AWS):
- **AWS CLI**: [Installation Guide](https://aws.amazon.com/cli/)
- **AWS Credentials**: `aws configure`
  ```bash
  aws configure
  # Enter: Access Key ID, Secret Access Key, Region (e.g., us-east-2)
  ```

**GCP**:
- **Google Cloud SDK**: [Installation Guide](https://cloud.google.com/sdk/docs/install)
- **Authentication**:
  ```bash
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project YOUR_PROJECT_ID
  ```

**Azure**:
- **Azure CLI**: [Installation Guide](https://docs.microsoft.com/cli/azure/install-azure-cli)
- **Authentication**:
  ```bash
  az login
  az account set --subscription "YOUR_SUBSCRIPTION_ID"
  ```

### GitHub Actions Pipeline

The pipeline automatically installs all tools. You only need to configure **GitHub Secrets**.

## 🔐 GitHub Actions Setup

### Required Secrets

Navigate to: **Repository Settings → Secrets and variables → Actions**

#### AWS Secrets (Always Required - for S3 Backend)
```
AWS_ACCESS_KEY_ID          # AWS Access Key ID
AWS_SECRET_ACCESS_KEY      # AWS Secret Access Key
```

**How to get AWS credentials:**
1. Go to AWS Console → IAM → Users → Your User → Security Credentials
2. Create Access Key → Download credentials
3. Add to GitHub Secrets

#### GCP Secrets (Required for GCP deployments)
```
GCP_SA_KEY                 # Service Account JSON Key (full JSON content)
```

**How to get GCP Service Account Key:**
1. Go to GCP Console → IAM & Admin → Service Accounts
2. Create Service Account (or use existing)
3. Grant roles: `Editor`, `Kubernetes Engine Admin` (for k8s mode)
4. Create Key (JSON) → Download
5. Copy **entire JSON content** (including `{` and `}`) to `GCP_SA_KEY` secret
   - ⚠️ **Important**: Copy only the JSON, no extra text like "=== BEGIN KEY ==="

**Example GCP Service Account Roles:**
- `Editor` (for general resource creation)
- `Kubernetes Engine Admin` (for GKE cluster creation)
- `Service Account User` (for service account usage)

#### Azure Secrets (Required for Azure deployments)
```
ARM_CLIENT_ID              # Azure Service Principal Client ID
ARM_CLIENT_SECRET          # Azure Service Principal Client Secret
ARM_SUBSCRIPTION_ID        # Azure Subscription ID
ARM_TENANT_ID             # Azure Tenant ID
```

**How to get Azure Service Principal:**
```bash
# Login to Azure
az login

# Create Service Principal
az ad sp create-for-rbac --name "multicloud-deployer" \
  --role contributor \
  --scopes /subscriptions/YOUR_SUBSCRIPTION_ID

# Output will show:
# {
#   "appId": "ARM_CLIENT_ID",
#   "password": "ARM_CLIENT_SECRET",
#   "tenant": "ARM_TENANT_ID"
# }

# Get Subscription ID
az account show --query id -o tsv  # This is ARM_SUBSCRIPTION_ID
```

Add all four values to GitHub Secrets.

## 🎯 Usage

### Local Deployment

#### Static Content Preparation (for Static Mode)

**Before deploying in static mode**, prepare your static website files:

1. **Create or use the `static-app-content/` directory** in the project root:
   ```bash
   mkdir -p static-app-content
   ```

2. **Add your static files** (HTML, CSS, JS, images, etc.):
   ```bash
   # Required: index.html (main page)
   # Optional: 404.html (error page), CSS, JS, images, etc.
   ```

3. **Example structure**:
   ```
   static-app-content/
   ├── index.html      # Required: Main page
   ├── 404.html        # Optional: Error page
   ├── styles.css      # Optional: Styles
   ├── script.js       # Optional: JavaScript
   └── images/         # Optional: Images folder
       └── logo.png
   ```

4. **Note**: The script will automatically create the directory and a sample `index.html` if missing, but you should replace it with your own content.

**Important**: All files in `static-app-content/` will be uploaded to all three clouds (AWS S3, Azure Storage, GCP Storage).

#### Interactive Mode
```bash
./deploy.sh
```

The script will:
1. Check prerequisites
2. Prompt for deployment options
3. Deploy infrastructure

#### Non-Interactive Mode (CLI Flags)
```bash
# Deploy to all clouds in container mode
./deploy.sh \
  --action deploy \
  --clouds aws,gcp,azure \
  --mode container \
  --image sumanthreddy2324/multi-cloud-demo:latest \
  --domain sumanthdev2324.com

# Destroy resources
./deploy.sh \
  --action destroy \
  --clouds aws,gcp,azure \
  --mode container
```

**Available Flags:**
- `-a, --action`: `deploy` or `destroy`
- `-c, --clouds`: Comma-separated list: `aws`, `gcp`, `azure`
- `-m, --mode`: `k8s`, `container`, or `static`
- `-i, --image`: Docker Hub image URI (e.g., `nginx:latest`)
- `-d, --domain`: Custom domain name (e.g., `example.com`)
- `-h, --help`: Show help message

### GitHub Actions Pipeline

#### Prerequisites Check

**Before running the pipeline**, ensure all required secrets are configured. The pipeline will automatically validate secrets and fail early with clear error messages if any are missing.

**Required Secrets:**
- **Always Required**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (for S3 backend)
- **For GCP**: `GCP_SA_KEY` (if deploying to GCP)
- **For Azure**: `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID` (if deploying to Azure)

The validation step runs automatically at the start of the pipeline and will show:
- ✅ Which secrets are configured
- ❌ Which secrets are missing
- Clear instructions on where to configure them

#### How to Trigger

1. Go to your GitHub repository
2. Click **Actions** tab
3. Select **Multi-Cloud Deployment Pipeline** workflow
4. Click **Run workflow** (dropdown on the right)
5. Fill in the inputs:
   - **Action**: `deploy` (to create) or `destroy` (to delete)
   - **Target Cloud**: `aws`, `azure`, `gcp`, or comma-separated (e.g., `aws,gcp,azure`)
   - **Deployment Mode**: `k8s`, `container`, `static`, or `all`
   - **Container Image**: Docker Hub URI (e.g., `nginx:latest`) - only for deploy
   - **Custom Domain**: Optional (e.g., `example.com`)
   - **Enable NAT Gateway**: `false` (default, saves costs) or `true` (for private subnets)
6. Click **Run workflow**

**Note**: If secrets are missing, the pipeline will fail immediately with a clear error message showing which secrets need to be configured.

#### Pipeline Inputs

| Input | Description | Required | Default | Example |
|-------|-------------|----------|---------|---------|
| `action` | Action to perform | Yes | `deploy` | `deploy` or `destroy` |
| `target_cloud` | Target clouds (comma-separated, no spaces) | Yes | `aws` | `aws,gcp,azure` |
| `deployment_mode` | Deployment mode | Yes | `k8s` | `k8s`, `container`, `static`, or `all` |
| `app_image` | Container image URI (Docker Hub) | No | `nginx:latest` | `sumanthreddy2324/multi-cloud-demo:latest` |
| `domain_name` | Custom domain name | No | (empty) | `example.com` |
| `enable_nat_gateway` | Enable NAT Gateway for AWS EKS (~$32/month) | No | `false` | `true` or `false` |

**Notes**:
- For `target_cloud`, use comma-separated values without spaces: `aws,gcp,azure` (not `aws, gcp, azure`)
- `action`: Choose `deploy` to create resources or `destroy` to delete them
- `deployment_mode`: Use `all` to deploy/destroy all modes (k8s, container, static) simultaneously
- `enable_nat_gateway`: Set to `true` only if you need private subnets (increases AWS costs)

#### Example Pipeline Runs

**Deploy to all clouds (container mode):**
- Action: `deploy`
- Target Cloud: `aws,gcp,azure`
- Deployment Mode: `container`
- Container Image: `sumanthreddy2324/multi-cloud-demo:latest`
- Custom Domain: `sumanthdev2324.com`
- Enable NAT Gateway: `false`

**Deploy to AWS only (Kubernetes):**
- Action: `deploy`
- Target Cloud: `aws`
- Deployment Mode: `k8s`
- Container Image: `nginx:latest`
- Custom Domain: `example.com`
- Enable NAT Gateway: `false`

**Deploy static website:**
- Action: `deploy`
- Target Cloud: `aws,gcp,azure`
- Deployment Mode: `static`
- Custom Domain: `example.com`
- **Note**: Ensure `static-app-content/` folder exists with your `index.html` and other static files before running

**Destroy all resources:**
- Action: `destroy`
- Target Cloud: `aws,gcp,azure`
- Deployment Mode: `all` (destroys all modes)
- Custom Domain: `example.com` (required if domain was used during deploy)

## 🌐 Custom Domain Configuration

### DNS Setup

When you provide a custom domain, the project automatically:

1. **Creates Route 53 Hosted Zone** (if domain is Route 53 registered)
2. **Updates Nameservers** (if domain is Route 53 registered)
3. **Creates SSL Certificates** (ACM for AWS, managed by services for others)
4. **Configures DNS Records**:
   - **AWS**: `aws.yourdomain.com` → App Runner / CloudFront / ALB
   - **Azure**: `azure.yourdomain.com` → Container Instance IP / Storage
   - **GCP**: `gcp.yourdomain.com` → Cloud Run / Storage

### DNS Propagation

- **Route 53 registered domains**: Nameservers updated automatically
- **External domains**: Update nameservers manually at your registrar
- **Propagation time**: 5 minutes to 48 hours (typically 1-2 hours)

### Multi-Cloud DNS Strategy

The project uses subdomains for multi-cloud deployments:
- `aws.yourdomain.com` → AWS services
- `azure.yourdomain.com` → Azure services
- `gcp.yourdomain.com` → GCP services

This allows you to access the same application deployed across all three clouds via different subdomains.

## 💰 Cost Optimization

### NAT Gateway (Disabled by Default)

- **Cost**: ~$32/month per NAT Gateway
- **Default**: Disabled (`enable_nat_gateway=false`)
- **Impact**: EKS nodes use public subnets (still secure with security groups)
- **Enable if needed**: Set `enable_nat_gateway=true` in variables

### Estimated Monthly Costs

**Kubernetes Mode:**
- EKS Cluster: ~$73/month
- EC2 Nodes: Varies by instance type
- NAT Gateway: ~$32/month (if enabled)

**Container Mode:**
- App Runner: Pay-per-request (~$0.007/vCPU-hour)
- Cloud Run: Pay-per-request (~$0.00002400/vCPU-second)
- Azure ACI: ~$0.000012/vCPU-second

**Static Mode:**
- S3 Storage: ~$0.023/GB/month
- CloudFront: ~$0.085/GB (first 10TB)
- Azure Storage: ~$0.0184/GB/month
- GCP Storage: ~$0.020/GB/month

## 🏗️ Architecture

### Deployment Modes

#### Kubernetes (k8s)
- **AWS**: EKS cluster with managed node groups
- **GCP**: GKE cluster (autopilot or standard)
- **Azure**: Not supported in k8s mode
- **Application**: Deployed via Ansible using Kubernetes manifests

#### Container
- **AWS**: App Runner (serverless container service)
- **GCP**: Cloud Run (serverless container service)
- **Azure**: Container Instances (ACI)
- **Image Mirroring**: Auto-mirrors Docker Hub images to ECR/ACR

#### Static
- **AWS**: S3 + CloudFront (CDN)
- **GCP**: Cloud Storage Bucket (static website)
- **Azure**: Storage Account (static website)
- **Content**: Serves files from `static-app-content/` directory
  - **Required**: `index.html` (main page)
  - **Optional**: `404.html` (error page), CSS, JS, images, etc.
  - **Location**: Place all static files in `static-app-content/` folder before deployment
  - **Auto-creation**: Directory is created automatically if missing (with sample content)
  - **SPA Routing**: Already configured to serve `index.html` for all routes (supports client-side routing)

## 🛣️ Application Routing

### How Routes Work

When you deploy a containerized application with multiple routes (e.g., `/cv`, `/achievements`, `/projects`), here's how each deployment mode handles them:

#### Kubernetes Mode (EKS/GKE)
- **Ingress Configuration**: Uses `pathType: Prefix` with `path: /`, which forwards **all paths** to your application
- **Application Routing**: Your containerized application (Express.js, Flask, React, etc.) handles all route logic
- **Example**: 
  - `https://yourdomain.com/` → Your app
  - `https://yourdomain.com/cv` → Your app (handled by app routing)
  - `https://yourdomain.com/achievements` → Your app (handled by app routing)
- **Works with**: Server-side routing (Express, Flask, Django) and client-side routing (React Router, Vue Router)

#### Container Mode (App Runner/Cloud Run/ACI)
- **Request Forwarding**: All HTTP requests are forwarded directly to your container
- **Application Routing**: Your application handles all route logic internally
- **Example**:
  - `https://aws.yourdomain.com/cv` → Container receives `/cv` path
  - `https://gcp.yourdomain.com/achievements` → Container receives `/achievements` path
- **Works with**: Any application framework that handles routing

#### Static Mode
- **File Serving**: Only serves static files (HTML, CSS, JS, images)
- **Client-Side Routing**: If using a Single Page Application (SPA) with client-side routing (React Router, Vue Router), you need to:
  - Configure your static hosting to serve `index.html` for all routes (404 fallback)
  - This is already configured for AWS (CloudFront), Azure, and GCP
- **Example**:
  - `https://aws.yourdomain.com/` → `index.html`
  - `https://aws.yourdomain.com/cv` → `index.html` (SPA handles routing client-side)
  - `https://aws.yourdomain.com/achievements` → `index.html` (SPA handles routing client-side)

### Important Notes

1. **Server-Side Routing**: For applications with server-side routing (Express.js, Flask, Django), routes work automatically in **K8s** and **Container** modes
2. **Client-Side Routing (SPAs)**: For React/Vue/Angular apps with client-side routing:
   - **Static Mode**: Already configured to serve `index.html` for all routes (404 fallback)
   - **Container/K8s Mode**: Your app server (nginx, Express, etc.) must be configured to serve `index.html` for all routes
3. **Path Prefix**: The current Ingress uses `pathType: Prefix` with `path: /`, which correctly forwards all paths to your application

### Example: Portfolio Application

If you deploy a portfolio app with routes like:
- `/` (home)
- `/cv` (resume)
- `/achievements` (awards)
- `/projects` (portfolio items)

**All routes will work automatically** in K8s and Container modes because:
- The load balancer/ingress forwards all requests to your container
- Your application (Express, Flask, React, etc.) handles the routing logic
- No additional configuration needed

## 🔧 Troubleshooting

### Common Issues

#### Routes Not Working (404 Errors)
- **Symptom**: Routes like `/cv`, `/achievements` return 404
- **For Container/K8s Mode**:
  - Check that your application handles these routes correctly
  - Verify your app server (Express, Flask, etc.) is configured to handle all paths
  - For SPAs: Ensure your server serves `index.html` for all routes (not just `/`)
- **For Static Mode**:
  - Ensure your SPA is configured for client-side routing
  - CloudFront/Azure/GCP are already configured to serve `index.html` for 404s
  - Check browser console for JavaScript errors

#### DNS Not Resolving
- **Symptom**: Domain/subdomain not accessible
- **Solution**: Wait for DNS propagation (24-48 hours max)
- **Check**: `dig @8.8.8.8 yourdomain.com NS`

#### Certificate Validation Pending
- **Symptom**: App Runner custom domain stuck in "pending_certificate_dns_validation"
- **Solution**: Ensure validation CNAME records exist in Route 53
- **Check**: `aws apprunner describe-custom-domains --service-arn <arn>`

#### Azure Container Not Accessible
- **Symptom**: Container IP accessible, but DNS not resolving
- **Solution**: DNS propagation issue (same as above)
- **Workaround**: Use IP address directly until DNS propagates

#### GCP Authentication Errors
- **Symptom**: `failed to parse service account key JSON`
- **Solution**: Ensure `GCP_SA_KEY` secret contains **only** the JSON (no extra text)

#### Terraform State Lock
- **Symptom**: `Error acquiring the state lock`
- **Solution**: Check DynamoDB table for stale locks, or wait for timeout

### Prerequisites Check

The `deploy.sh` script automatically checks prerequisites. If something is missing, it will show installation instructions.

## 📚 Additional Resources

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Azure Provider Docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Terraform GCP Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Ansible Kubernetes Collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally and via pipeline
5. Submit a pull request

## 📝 License

This project is open source and available under the MIT License.

## 🆘 Support

For issues or questions:
1. Check the [Troubleshooting](#-troubleshooting) section
2. Review GitHub Issues
3. Create a new issue with:
   - Deployment mode
   - Target clouds
   - Error messages
   - Terraform/Ansible logs

---

**Note**: Always test in a non-production environment first. Destroy resources when not in use to avoid unnecessary costs.


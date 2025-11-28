#!/bin/bash
set -e

echo "Building Deployment Container..."
docker build -t multicloud-deployer .

echo "Running Deployment Container..."
echo "Mounting current directory to /app"
echo "Mounting ~/.aws to /root/.aws (for credentials)"

# Run interactively (-it) so you can answer the prompts
# Mount current dir (-v $(pwd):/app) so generated files (kubeconfig) are saved to host
# Mount AWS creds (-v ~/.aws:/root/.aws) so the container uses your local creds
docker run -it --rm \
  -v "$(pwd):/app" \
  -v "$HOME/.aws:/root/.aws" \
  multicloud-deployer


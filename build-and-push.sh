#!/bin/bash
set -e

IMAGE_NAME="sumanthreddy2324/multi-cloud-demo:latest"

echo "🐳 Building Docker image: $IMAGE_NAME..."
# Build from static-app-content directory
docker build -t "$IMAGE_NAME" ./static-app-content

echo "🚀 Pushing image to Docker Hub..."
docker push "$IMAGE_NAME"

echo "✅ Success! Image pushed: $IMAGE_NAME"
echo "📋 Use this in your deployment pipeline:"
echo "   app_image: $IMAGE_NAME"


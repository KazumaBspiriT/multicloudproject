# modules/aws-static/outputs.tf

# This output exports the static website endpoint URL, which is used by the
# root module and the CI/CD pipeline's smoke test.
output "website_url" {
  description = "The public endpoint of the static website."
  # The value is derived from the S3 bucket's website configuration resource.
  value       = aws_s3_bucket_website_configuration.website_config.website_endpoint
}
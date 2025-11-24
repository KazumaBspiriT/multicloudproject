# modules/aws-static/main.tf

variable "project_name" { type = string }
variable "aws_region" { type = string }
variable "static_content_path" { type = string }

# 1. Create S3 Bucket (Name must be globally unique)
resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.project_name}-${var.aws_region}-static" # Using project name + region for uniqueness
  
  tags = {
    Name = "${var.project_name}-static-website"
  }
}

# 2. Enable Static Website Hosting
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

# 3. Block Public Access (to ensure website config works, S3 blocks all public access by default)
# Note: For static hosting, we must allow public read access via policy.
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.website_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Set Bucket Policy to allow Public Read access
data "aws_iam_policy_document" "allow_public_read" {
  statement {
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.website_bucket.arn}/*", # Policy applies to all objects
    ]
  }
}

resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = data.aws_iam_policy_document.allow_public_read.json
}


# 5. Upload website files (Assumes content is in the defined path)
resource "null_resource" "upload_files" {
  triggers = {
    # Re-run the upload if content files change
    content_hash = filesha256(join("", [for f in fileset(var.static_content_path, "**") : file("${var.static_content_path}/${f}")]))
  }

  provisioner "local-exec" {
    command = "aws s3 sync ${var.static_content_path} s3://${aws_s3_bucket.website_bucket.id} --delete"
    # Requires AWS CLI to be installed and configured
  }
  
  # Ensure policy and website config are applied before uploading
  depends_on = [
    aws_s3_bucket_website_configuration.website_config,
    aws_s3_bucket_policy.public_read_policy
  ]
}

# Outputs (same format as K8s output)
output "website_url" {
  description = "The public endpoint of the static website."
  value       = aws_s3_bucket_website_configuration.website_config.website_endpoint
}
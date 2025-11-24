# Provisions an AWS S3 bucket for static website hosting and uploads content.

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

# 1) S3 bucket (needs global uniqueness)
resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.project_name}-${var.aws_region}-static-${random_string.suffix.result}"

  tags = {
    Project    = var.project_name
    ManagedBy  = "Terraform"
    CostCenter = "FreeTier"
  }
}

# 2) Static website hosting
resource "aws_s3_bucket_website_configuration" "website_config" {
  bucket = aws_s3_bucket.website_bucket.id

  index_document { suffix = "index.html" }
  error_document { key    = "404.html" }
}

# 3) Public access settings (website endpoints require public reads if you don’t use CloudFront)
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.website_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4) Bucket policy: public read of objects
data "aws_iam_policy_document" "allow_public_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.website_bucket.id
  policy = data.aws_iam_policy_document.allow_public_read.json
}

# 5) Upload local site files (requires awscli available where Terraform runs)
resource "null_resource" "upload_files" {
  triggers = {
    content_hash = filesha256(join("", [
      for f in fileset(var.static_content_path, "**") :
      file("${var.static_content_path}/${f}")
    ]))
  }

  provisioner "local-exec" {
    command = "aws s3 sync ${var.static_content_path} s3://${aws_s3_bucket.website_bucket.id} --delete --acl public-read"
  }

  depends_on = [
    aws_s3_bucket_website_configuration.website_config,
    aws_s3_bucket_policy.public_read_policy
  ]
}

output "bucket_name" {
  value = aws_s3_bucket.website_bucket.bucket
}

# NOTE: S3 static website endpoint is HTTP-only.
# If you need HTTPS, front it with CloudFront (different module).
output "website_endpoint" {
  value = aws_s3_bucket_website_configuration.website_config.website_endpoint
}

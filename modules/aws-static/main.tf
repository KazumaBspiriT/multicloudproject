# modules/aws-static/main.tf
# Provisions an AWS S3 bucket configured for static website hosting, 
# along with necessary policies and content upload mechanism.

# 1. Create S3 Bucket (Name must be globally unique)
resource "aws_s3_bucket" "website_bucket" {
  bucket = "${var.project_name}-${var.aws_region}-static-${random_string.suffix.result}" # Use random suffix for uniqueness
  
  tags = {
    "Project" = var.project_name
    "ManagedBy" = "Terraform"
    "CostCenter" = "FreeTier"
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

# 3. Block Public Access (to ensure website config works, S3 needs explicit policy)
# We set these to false to allow public read via the bucket policy below.
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket                  = aws_s3_bucket.website_bucket.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# 4. Set Bucket Policy to allow Public Read access (required for static hosting)
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


# 5. Upload website files (using AWS CLI on the GitHub Runner)
# We use the null_resource and local-exec since Terraform does not manage file contents well
resource "null_resource" "upload_files" {
  triggers = {
    # Hashing file content forces a re-upload on file change
    content_hash = filesha256(join("", [for f in fileset(var.static_content_path, "**") : file("${var.static_content_path}/${f}")]))
  }

  provisioner "local-exec" {
    # This command requires the 'aws' CLI to be available on the runner
    command = "aws s3 sync ${var.static_content_path} s3://${aws_s3_bucket.website_bucket.id} --delete --acl public-read"
  }
  
  # Ensure policy and website config are applied before uploading
  depends_on = [
    aws_s3_bucket_website_configuration.website_config,
    aws_s3_bucket_policy.public_read_policy
  ]
}

# Helper to ensure unique bucket name
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}
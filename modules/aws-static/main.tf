# modules/aws-static/main.tf
# Private S3 + CloudFront (OAC). HTTPS CDN URL; account-level Block Public Access may remain ON.

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

# 1) Private S3 bucket
resource "aws_s3_bucket" "site" {
  bucket        = "${var.project_name}-${var.aws_region}-static-${random_string.suffix.result}"
  force_destroy = true

  tags = {
    Project    = var.project_name
    ManagedBy  = "Terraform"
    CostCenter = "FreeTier"
  }
}

resource "aws_s3_bucket_ownership_controls" "own" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "bpa" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2) CloudFront OAC (so CloudFront can read the private S3 origin)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for private S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 3) CloudFront distribution (serves index.html over HTTPS)
resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  depends_on = [aws_s3_bucket_public_access_block.bpa]
}

# 4) Bucket policy: allow ONLY this CloudFront distribution to read (not public!)
data "aws_iam_policy_document" "cf_read" {
  statement {
    sid     = "AllowCloudFrontRead"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.site.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.cf_read.json
}

# 5) Upload local site files (needs awscli on the runner/machine)
locals {
  content_dir   = abspath(var.static_content_path)
  content_files = fileset(local.content_dir, "**")
  content_hash  = length(local.content_files) == 0 ? "empty" : sha256(join("", [
    for f in local.content_files : filesha256("${local.content_dir}/${f}")
  ]))
}

resource "null_resource" "upload" {
  count = length(local.content_files) == 0 ? 0 : 1

  triggers = {
    content_hash = local.content_hash
  }

  provisioner "local-exec" {
    command = "aws s3 sync ${local.content_dir} s3://${aws_s3_bucket.site.id} --delete"
  }

  depends_on = [
    aws_s3_bucket_ownership_controls.own,
    aws_s3_bucket_public_access_block.bpa,
    aws_s3_bucket_policy.site
  ]
}

# Outputs
output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.cdn.domain_name}"
}

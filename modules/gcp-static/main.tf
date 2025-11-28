# modules/gcp-static/main.tf

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

# 1. Public GCS Bucket
resource "google_storage_bucket" "site" {
  name          = "${var.project_name}-${var.gcp_region}-static-${random_string.suffix.result}"
  location      = var.gcp_region
  force_destroy = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  uniform_bucket_level_access = true
}

# 2. Make bucket public
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# 3. Upload files
locals {
  content_dir   = abspath(var.static_content_path)
  content_files = fileset(local.content_dir, "**")
  content_hash = length(local.content_files) == 0 ? "empty" : sha256(join("", [
    for f in local.content_files : filesha256("${local.content_dir}/${f}")
  ]))
}

resource "null_resource" "upload" {
  count = length(local.content_files) == 0 ? 0 : 1

  triggers = {
    content_hash = local.content_hash
  }

  provisioner "local-exec" {
    # Assumes gsutil is installed and authenticated
    command = "gsutil -m rsync -R ${local.content_dir} gs://${google_storage_bucket.site.name}"
  }

  depends_on = [google_storage_bucket.site]
}


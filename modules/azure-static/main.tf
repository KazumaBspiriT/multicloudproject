# modules/azure-static/main.tf

resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-static-rg"
  location = var.azure_region
}

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

locals {
  # Azure Storage Account name requirements:
  # - Only lowercase letters and numbers
  # - 3-24 characters
  # - Globally unique
  sanitized_name = substr(replace(lower(var.project_name), "-", ""), 0, 18)
  storage_name   = "st${local.sanitized_name}${random_string.suffix.result}"
}

resource "azurerm_storage_account" "sa" {
  name                     = local.storage_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }
}

# Upload content
locals {
  content_dir   = abspath(var.static_content_path)
  content_files = fileset(local.content_dir, "**")
  content_hash  = length(local.content_files) == 0 ? "empty" : sha256(join("", [
    for f in local.content_files : filesha256("${local.content_dir}/${f}")
  ]))
}

# Since Azure provider doesn't have a recursive "sync" like AWS CLI, 
# we'll use az CLI via null_resource for efficiency, similar to other modules.
resource "null_resource" "upload" {
  count = length(local.content_files) == 0 ? 0 : 1

  triggers = {
    content_hash = local.content_hash
  }

  provisioner "local-exec" {
    command = "az storage blob upload-batch -s ${local.content_dir} -d '$web' --account-name ${azurerm_storage_account.sa.name} --auth-mode login"
  }
}


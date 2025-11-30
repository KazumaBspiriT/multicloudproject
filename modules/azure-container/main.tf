# modules/azure-container/main.tf

resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
  numeric = true
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-container-rg"
  location = var.azure_region
}

resource "azurerm_container_group" "aci" {
  name                = "${var.project_name}-aci-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  os_type             = "Linux"
  dns_name_label      = "${var.project_name}-${substr(md5(var.project_name), 0, 8)}"

  container {
    name   = "${var.project_name}-container"
    image  = var.app_image
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = {
    Environment = "dev"
    Project     = var.project_name
  }

  lifecycle {
    # Retry on registry errors (Docker Hub rate limiting)
    create_before_destroy = false
    ignore_changes = [
      # Ignore changes that might cause conflicts
    ]
  }
}


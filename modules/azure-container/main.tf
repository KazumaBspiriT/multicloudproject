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

# Create ACR to avoid Docker Hub rate limits (Mirroring)
locals {
  # ACR name must be alphanumeric only
  acr_name = replace("${var.project_name}acr${random_string.suffix.result}", "-", "")
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Mirror the public image to ACR
resource "null_resource" "mirror_image" {
  triggers = {
    image = var.app_image
    acr   = azurerm_container_registry.acr.login_server
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      echo "Mirroring ${var.app_image} to Azure ACR..."
      # Login to ACR
      docker login ${azurerm_container_registry.acr.login_server} \
        --username ${azurerm_container_registry.acr.admin_username} \
        --password ${azurerm_container_registry.acr.admin_password}
      
      docker pull ${var.app_image}
      docker tag ${var.app_image} ${azurerm_container_registry.acr.login_server}/mirror:latest
      docker push ${azurerm_container_registry.acr.login_server}/mirror:latest
    EOT
  }
}

resource "azurerm_container_group" "aci" {
  name                = "${var.project_name}-aci-${random_string.suffix.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  ip_address_type     = "Public"
  os_type             = "Linux"
  dns_name_label      = "${var.project_name}-${substr(md5(var.project_name), 0, 8)}"

  # Use ACR credentials
  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }

  container {
    name   = "${var.project_name}-container"
    image  = "${azurerm_container_registry.acr.login_server}/mirror:latest"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }
  }
  
  depends_on = [null_resource.mirror_image]

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


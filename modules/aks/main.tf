# modules/aks/main.tf

resource "azurerm_resource_group" "rg" {
  name     = "${var.project_name}-rg"
  location = var.azure_region
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.project_name}-aks"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.project_name}-aks"
  # Use cluster_version variable (defaults to 1.31)
  # For Azure, use 1.31.x which supports KubernetesOfficial (standard tier, works with free credits)
  kubernetes_version  = var.cluster_version

  default_node_pool {
    name       = "default"
    node_count = 1
    # Use standard_dc2s_v3 (small DC series) - available in free tier subscriptions
    # Alternative options if this fails: standard_ec2as_v5, standard_fx2ms_v2
    vm_size    = "standard_dc2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "dev"
    Project     = var.project_name
  }
}

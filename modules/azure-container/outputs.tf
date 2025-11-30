# modules/azure-container/outputs.tf

output "service_url" {
  value = "http://${azurerm_container_group.aci.fqdn}"
}

output "fqdn" {
  value = azurerm_container_group.aci.fqdn
}

output "ip_address" {
  value = azurerm_container_group.aci.ip_address
}

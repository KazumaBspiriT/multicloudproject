# modules/azure-static/outputs.tf

output "website_url" {
  value = azurerm_storage_account.sa.primary_web_endpoint
}

output "storage_account_name" {
  value = azurerm_storage_account.sa.name
}


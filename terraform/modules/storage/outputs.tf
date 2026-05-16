output "storage_account_name" {
  description = "Name of the storage account holding build artifacts"
  value       = azurerm_storage_account.this.name
}

output "storage_account_id" {
  description = "Resource ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "artifacts_container_name" {
  description = "Container holding React build outputs"
  value       = azurerm_storage_container.artifacts.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint URL"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "shared_image_gallery_name" {
  description = "Name of the Shared Image Gallery — Packer publishes here"
  value       = azurerm_shared_image_gallery.this.name
}

output "shared_image_name" {
  description = "Name of the image definition inside the gallery"
  value       = azurerm_shared_image.nginx_react.name
}

output "shared_image_id" {
  description = "Resource ID of the image definition (not a specific version)"
  value       = azurerm_shared_image.nginx_react.id
}

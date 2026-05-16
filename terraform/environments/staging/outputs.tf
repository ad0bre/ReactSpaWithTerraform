output "resource_group_name" {
  description = "Resource group containing all staging resources"
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region this environment is deployed in"
  value       = var.location
}

output "vnet_id" {
  description = "ID of the staging VNet"
  value       = module.network.vnet_id
}

output "storage_account_name" {
  description = "Storage account holding React build artifacts — CI uploads dist/ here"
  value       = module.storage.storage_account_name
}

output "artifacts_container_name" {
  description = "Container name within the storage account"
  value       = module.storage.artifacts_container_name
}

output "shared_image_gallery_name" {
  description = "SIG name — Packer publishes image versions here"
  value       = module.storage.shared_image_gallery_name
}

output "shared_image_name" {
  description = "Image definition name within the SIG"
  value       = module.storage.shared_image_name
}

output "load_balancer_public_ip" {
  description = "Public IP of the load balancer"
  value       = module.compute.load_balancer_public_ip
}

output "app_url" {
  description = "URL to reach the deployed app"
  value       = "http://${module.compute.load_balancer_public_ip}"
}

output "vmss_id" {
  description = "Resource ID of the VM scale set — useful for manual rolling upgrades"
  value       = module.compute.vmss_id
}

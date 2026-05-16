output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.this.name
}

output "public_subnet_id" {
  description = "ID of the public subnet (load balancer)"
  value       = azurerm_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet (VMSS)"
  value       = azurerm_subnet.private.id
}

output "public_subnet_cidr" {
  description = "CIDR of the public subnet — useful for downstream NSG rules"
  value       = var.public_subnet_cidr
}

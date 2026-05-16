output "load_balancer_public_ip" {
  description = "Public IP of the load balancer — point your browser here"
  value       = azurerm_public_ip.lb.ip_address
}

output "load_balancer_id" {
  description = "Resource ID of the load balancer"
  value       = azurerm_lb.this.id
}

output "backend_pool_id" {
  description = "Backend pool ID — useful if external systems need to attach to it"
  value       = azurerm_lb_backend_address_pool.this.id
}

output "vmss_id" {
  description = "Resource ID of the VM scale set"
  value       = azurerm_linux_virtual_machine_scale_set.this.id
}

output "vmss_principal_id" {
  description = "Managed identity principal ID of the VMSS — grant this Storage Blob read"
  value       = azurerm_linux_virtual_machine_scale_set.this.identity[0].principal_id
}

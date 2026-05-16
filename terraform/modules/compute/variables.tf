variable "project" {
  description = "Short project name"
  type        = string
}

variable "environment" {
  description = "Environment name: 'staging' or 'prod'"
  type        = string
  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "environment must be 'staging' or 'prod'."
  }
}

variable "resource_group_name" {
  description = "Resource group the compute resources live in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "private_subnet_id" {
  description = "ID of the subnet where VMSS instances are placed"
  type        = string
}

variable "vm_size" {
  description = "VM SKU (e.g. Standard_B1s for staging, Standard_B2s for prod)"
  type        = string
  default     = "Standard_B1s"
}

variable "instance_count" {
  description = "Initial / fixed instance count. Ignored at runtime if autoscale is on."
  type        = number
  default     = 1
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the azureuser admin account"
  type        = string
}

variable "use_custom_image" {
  description = "If false, use stock Ubuntu 22.04 from Marketplace. If true, pull from SIG."
  type        = bool
  default     = false
}

variable "shared_image_gallery_name" {
  description = "Name of the SIG (required when use_custom_image = true)"
  type        = string
  default     = ""
}

variable "shared_image_name" {
  description = "Image definition name within the SIG (required when use_custom_image = true)"
  type        = string
  default     = ""
}

variable "image_version" {
  description = "Specific image version to deploy (e.g. '1.0.0' or 'latest')"
  type        = string
  default     = "latest"
}

variable "enable_autoscale" {
  description = "Enable CPU-based autoscale (typically true in prod, false in staging)"
  type        = bool
  default     = false
}

variable "autoscale_min" {
  description = "Minimum instance count when autoscale is on"
  type        = number
  default     = 2
}

variable "autoscale_max" {
  description = "Maximum instance count when autoscale is on"
  type        = number
  default     = 4
}

variable "autoscale_default" {
  description = "Default instance count when autoscale is on"
  type        = number
  default     = 2
}

variable "backend_pool_override_id" {
  description = "Optional: override the LB backend pool ID. Leave null to use the pool created in this module."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

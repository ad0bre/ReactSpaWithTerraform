variable "project" {
  description = "Short project name"
  type        = string
  default     = "helloapp"
}

variable "environment" {
  description = "Environment name — should always be 'prod' in this file"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

# ----------------------------------------------------------------------------
# Network
# ----------------------------------------------------------------------------

variable "vnet_cidr" {
  description = "CIDR for the prod VNet. Must not overlap with staging."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public (load balancer) subnet"
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private (VMSS) subnet"
  type        = string
  default     = "10.20.2.0/24"
}

# ----------------------------------------------------------------------------
# Storage
# ----------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "GRS in prod for cross-region durability"
  type        = string
  default     = "GRS"
}

# ----------------------------------------------------------------------------
# Compute
# ----------------------------------------------------------------------------

variable "vm_size" {
  description = "VM SKU — larger for production workloads"
  type        = string
  default     = "Standard_B2s"
}

variable "instance_count" {
  description = "Initial instance count. Once autoscale is active, this is ignored."
  type        = number
  default     = 2
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the azureuser admin account on VMSS instances"
  type        = string
}

variable "enable_autoscale" {
  description = "Autoscale enabled in prod"
  type        = bool
  default     = true
}

variable "autoscale_min" {
  description = "Minimum instance count under autoscale"
  type        = number
  default     = 2
}

variable "autoscale_max" {
  description = "Maximum instance count under autoscale"
  type        = number
  default     = 6
}

variable "autoscale_default" {
  description = "Default instance count under autoscale"
  type        = number
  default     = 2
}

variable "use_custom_image" {
  description = "First apply: false (uses stock Ubuntu). After Packer publishes: true."
  type        = bool
  default     = false
}

variable "image_version" {
  description = "Image version from SIG. In prod, pin to a specific version rather than 'latest'."
  type        = string
  default     = "latest"
}

variable "tags" {
  description = "Additional tags merged with common tags"
  type        = map(string)
  default     = {}
}

variable "project" {
  description = "Short project name — used in all resource names"
  type        = string
  default     = "helloapp"
}

variable "environment" {
  description = "Environment name — should always be 'staging' in this file"
  type        = string
  default     = "staging"
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
  description = "CIDR for the staging VNet. Must not overlap with prod."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public (load balancer) subnet"
  type        = string
  default     = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private (VMSS) subnet"
  type        = string
  default     = "10.10.2.0/24"
}

# ----------------------------------------------------------------------------
# Storage
# ----------------------------------------------------------------------------

variable "storage_replication_type" {
  description = "LRS in staging (cheap, single-region)"
  type        = string
  default     = "LRS"
}

# ----------------------------------------------------------------------------
# Compute
# ----------------------------------------------------------------------------

variable "vm_size" {
  description = "VM SKU — small/cheap for staging"
  type        = string
  default     = "Standard_B1s"
}

variable "instance_count" {
  description = "Number of VMSS instances. Single instance is fine for staging."
  type        = number
  default     = 1
}

variable "admin_ssh_public_key" {
  description = "SSH public key for the azureuser admin account on VMSS instances"
  type        = string
  # No default — must be provided via tfvars or env var
}

variable "enable_autoscale" {
  description = "Autoscale is disabled in staging — fixed single instance"
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------
# Image selection (seed bootstrap pattern)
# ----------------------------------------------------------------------------

variable "use_custom_image" {
  description = "First apply: false (uses stock Ubuntu). After Packer publishes: true."
  type        = bool
  default     = false
}

variable "image_version" {
  description = "Image version from the Shared Image Gallery (e.g. '1.0.0' or 'latest')"
  type        = string
  default     = "latest"
}

# ----------------------------------------------------------------------------
# Tagging
# ----------------------------------------------------------------------------

variable "tags" {
  description = "Additional tags merged with common tags"
  type        = map(string)
  default     = {}
}

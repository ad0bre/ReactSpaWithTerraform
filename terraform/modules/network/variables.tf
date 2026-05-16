variable "project" {
  description = "Short project name, used in resource naming (e.g. 'helloapp')"
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
  description = "Resource group the network resources live in"
  type        = string
}

variable "location" {
  description = "Azure region (e.g. 'westeurope')"
  type        = string
}

variable "vnet_cidr" {
  description = "CIDR for the virtual network. Use non-overlapping ranges between envs."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (load balancer)"
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (VMSS)"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

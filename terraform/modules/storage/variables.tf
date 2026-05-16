variable "project" {
  description = "Short project name, used in resource naming (lowercase alphanumeric only for storage account compatibility)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.project)) && length(var.project) <= 11
    error_message = "project must be lowercase alphanumeric, ≤11 chars (storage account names are capped at 24)."
  }
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
  description = "Resource group the storage and image gallery live in"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "replication_type" {
  description = "Storage replication type. LRS for staging, GRS for prod is typical."
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "GZRS"], var.replication_type)
    error_message = "replication_type must be one of LRS, GRS, ZRS, GZRS."
  }
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

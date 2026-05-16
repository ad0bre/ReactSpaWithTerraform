terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
  numeric = true

  keepers = {
    environment = var.environment
    project     = var.project
  }
}

resource "azurerm_storage_account" "this" {
  name                = "st${var.project}${var.environment}${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = var.replication_type
  account_kind             = "StorageV2"

  # Security hardening — even for a class project these matter
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # Packer uploads via shared key; could be tightened to RBAC-only

  blob_properties {
    versioning_enabled = true # keeps old dist/ uploads recoverable
  }

  tags = var.tags
}

# Private container — React build outputs land here from CI
resource "azurerm_storage_container" "artifacts" {
  name                  = "artifacts"
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}

resource "azurerm_shared_image_gallery" "this" {
  name                = "sig_${var.project}_${var.environment}" # SIG names allow underscores, not dashes
  resource_group_name = var.resource_group_name
  location            = var.location
  description         = "Image gallery for ${var.project} ${var.environment}"

  tags = var.tags
}

resource "azurerm_shared_image" "nginx_react" {
  name                = "nginx-react"
  gallery_name        = azurerm_shared_image_gallery.this.name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  hyper_v_generation  = "V2"

  identifier {
    publisher = "helloapp"
    offer     = "nginx-react"
    sku       = "ubuntu-22-04"
  }

  tags = var.tags
}

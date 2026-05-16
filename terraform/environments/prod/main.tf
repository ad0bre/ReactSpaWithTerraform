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

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "REPLACE_VIA_INIT_BACKEND_CONFIG"
    container_name       = "tfstate"
    key                  = "prod.tfstate"
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Prod safety: don't allow accidental RG deletion when resources remain
      prevent_deletion_if_contains_resources = true
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Environment = "prod"
    Project     = var.project
    ManagedBy   = "Terraform"
  })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.project}-${var.environment}"
  location = var.location
  tags     = local.common_tags
}

module "network" {
  source = "../../modules/network"

  project             = var.project
  environment         = var.environment
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  vnet_cidr           = var.vnet_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr

  tags = local.common_tags
}

module "storage" {
  source = "../../modules/storage"

  project             = var.project
  environment         = var.environment
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  replication_type = var.storage_replication_type

  tags = local.common_tags
}

module "compute" {
  source = "../../modules/compute"

  project             = var.project
  environment         = var.environment
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location

  private_subnet_id    = module.network.private_subnet_id
  vm_size              = var.vm_size
  instance_count       = var.instance_count
  admin_ssh_public_key = var.admin_ssh_public_key

  use_custom_image          = var.use_custom_image
  shared_image_gallery_name = module.storage.shared_image_gallery_name
  shared_image_name         = module.storage.shared_image_name
  image_version             = var.image_version

  # Autoscale enabled in prod — handles real traffic patterns
  enable_autoscale  = var.enable_autoscale
  autoscale_min     = var.autoscale_min
  autoscale_max     = var.autoscale_max
  autoscale_default = var.autoscale_default

  tags = local.common_tags

  depends_on = [module.storage]
}

resource "azurerm_role_assignment" "vmss_blob_reader" {
  scope                = module.storage.storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.compute.vmss_principal_id
}

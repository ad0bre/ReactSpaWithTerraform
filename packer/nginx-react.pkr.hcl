# ============================================================================
# Packer template: nginx-react
#
# Builds a custom Azure VM image:
#   1. Start from Ubuntu 22.04 LTS marketplace image
#   2. Install nginx
#   3. Pull React build artifacts from the env's Storage Account
#   4. Configure nginx for SPA routing
#   5. Publish as a new version in the Shared Image Gallery
#
# Run with:
#   packer init .
#   packer build -var-file=staging.pkrvars.hcl .
# ============================================================================

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = ">= 2.0.0"
    }
  }
}

# ----------------------------------------------------------------------------
# Inputs — passed per-env via .pkrvars.hcl files
# ----------------------------------------------------------------------------

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "location" {
  type        = string
  description = "Azure region for the build VM and final image"
  default     = "westeurope"
}

variable "build_resource_group_name" {
  type        = string
  description = "Resource group holding the temporary build VM (auto-created and destroyed). Separate from target RG."
  default     = "rg-packer-builds"
}

variable "target_resource_group_name" {
  type        = string
  description = "Resource group containing the Shared Image Gallery and Storage Account (the env's RG, e.g. rg-helloapp-staging)"
}

variable "shared_image_gallery_name" {
  type        = string
  description = "Name of the Shared Image Gallery to publish to (e.g. sig_helloapp_staging)"
}

variable "shared_image_name" {
  type        = string
  description = "Image definition name within the gallery (e.g. nginx-react)"
  default     = "nginx-react"
}

variable "image_version" {
  type        = string
  description = "Semver version to publish (e.g. 1.0.0). Must be unique per gallery."
}

variable "storage_account_name" {
  type        = string
  description = "Storage account holding the React dist/ to bake in"
}

variable "artifacts_container_name" {
  type        = string
  description = "Container within the storage account holding dist artifacts"
  default     = "artifacts"
}

variable "artifacts_blob_prefix" {
  type        = string
  description = "Blob prefix / path inside the container (e.g. 'dist/' or a build-id)"
  default     = "latest/"
}

variable "replication_regions" {
  type        = list(string)
  description = "Regions to replicate the image version into"
  default     = ["westeurope"]
}

variable "vm_size" {
  type        = string
  description = "Build VM size — small is fine, it's transient"
  default     = "Standard_B2s"
}

# ----------------------------------------------------------------------------
# Local values — computed once
# ----------------------------------------------------------------------------

locals {
  # ISO 8601 timestamp for build metadata
  build_timestamp = formatdate("YYYYMMDD-hhmmss", timestamp())

  common_tags = {
    BuiltBy      = "Packer"
    BuildVersion = var.image_version
    BuildTime    = local.build_timestamp
    ImageType    = "nginx-react"
  }
}

# ----------------------------------------------------------------------------
# Source: Azure ARM builder publishing to Shared Image Gallery
#
# Authentication: relies on Azure CLI login (local) or environment variables
# (CI). With OIDC in GitHub Actions, the azure/login action handles it.
# ----------------------------------------------------------------------------

source "azure-arm" "nginx_react" {
  # Auth via ambient credentials (CLI / env vars / OIDC token)
  subscription_id = var.subscription_id

  # Base image: stock Ubuntu 22.04 LTS gen2
  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts-gen2"
  vm_size         = var.vm_size
  location        = var.location

  # Temporary build resource group (Packer creates + destroys this each run)
  build_resource_group_name = var.build_resource_group_name

  # Publish target: a new version inside the Shared Image Gallery
  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.target_resource_group_name
    gallery_name         = var.shared_image_gallery_name
    image_name           = var.shared_image_name
    image_version        = var.image_version
    replication_regions  = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  # Required: managed disk for Linux gen2 SIG-destined images
  managed_image_name                = "packer-${var.shared_image_name}-${replace(var.image_version, ".", "-")}"
  managed_image_resource_group_name = var.target_resource_group_name

  # SSH config — Packer auto-generates a one-shot key
  communicator                      = "ssh"
  ssh_username                      = "packer"
  ssh_clear_authorized_keys         = true # remove the ephemeral key from the final image

  # Tags applied to the final image version
  azure_tags = local.common_tags
}

# ----------------------------------------------------------------------------
# Build: provisioner steps
# ----------------------------------------------------------------------------

build {
  name    = "nginx-react"
  sources = ["source.azure-arm.nginx_react"]

  # ---- Step 1: install nginx and tooling ----
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/01-install-packages.sh",
    ]
  }

  # ---- Step 2: drop in the nginx site config ----
  provisioner "file" {
    source      = "${path.root}/files/nginx-spa.conf"
    destination = "/tmp/nginx-spa.conf"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/02-configure-nginx.sh",
    ]
  }

  # ---- Step 3: pull dist/ from Storage Account into /var/www/html ----
  # The build VM uses its system-assigned identity (granted at provision time
  # via the Packer build resource group's role assignments) OR a SAS token
  # passed via env var. We use the simpler az login + managed identity path.
  provisioner "shell" {
    environment_vars = [
      "STORAGE_ACCOUNT=${var.storage_account_name}",
      "CONTAINER=${var.artifacts_container_name}",
      "BLOB_PREFIX=${var.artifacts_blob_prefix}",
    ]
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/03-fetch-dist.sh",
    ]
  }

  # ---- Step 4: final cleanup so the image is reusable ----
  # The Azure-recommended deprovision step strips machine-specific data
  # (SSH host keys, machine-id, cloud-init state).
  provisioner "shell" {
    execute_command   = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline_shebang    = "/bin/sh -x"
    expect_disconnect = true
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}

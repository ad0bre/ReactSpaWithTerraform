terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

resource "azurerm_public_ip" "lb" {
  name                = "pip-lb-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard" # Standard SKU required for VMSS-backed LB

  tags = var.tags
}

resource "azurerm_lb" "this" {
  name                = "lb-${var.project}-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "frontend"
    public_ip_address_id = azurerm_public_ip.lb.id
  }

  tags = var.tags
}

resource "azurerm_lb_backend_address_pool" "this" {
  name            = "backend-pool"
  loadbalancer_id = azurerm_lb.this.id
}

resource "azurerm_lb_probe" "http" {
  name                = "http-probe"
  loadbalancer_id     = azurerm_lb.this.id
  protocol            = "Http"
  port                = 80
  request_path        = "/"
  interval_in_seconds = 15
  number_of_probes    = 2
}

resource "azurerm_lb_rule" "http" {
  name                           = "http-rule"
  loadbalancer_id                = azurerm_lb.this.id
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = "frontend"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.this.id]
  probe_id                       = azurerm_lb_probe.http.id
  disable_outbound_snat          = true
}

resource "azurerm_lb_outbound_rule" "this" {
  name                    = "outbound-rule"
  loadbalancer_id         = azurerm_lb.this.id
  protocol                = "All"
  backend_address_pool_id = azurerm_lb_backend_address_pool.this.id

  frontend_ip_configuration {
    name = "frontend"
  }
}

locals {
  # Marketplace Ubuntu 22.04 LTS reference (used when no custom image yet)
  marketplace_publisher = "Canonical"
  marketplace_offer     = "0001-com-ubuntu-server-jammy"
  marketplace_sku       = "22_04-lts-gen2"
  marketplace_version   = "latest"
}

# When use_custom_image is true, look up the specific image version from SIG
data "azurerm_shared_image_version" "selected" {
  count               = var.use_custom_image ? 1 : 0
  name                = var.image_version
  image_name          = var.shared_image_name
  gallery_name        = var.shared_image_gallery_name
  resource_group_name = var.resource_group_name
}

resource "azurerm_linux_virtual_machine_scale_set" "this" {
  name                = "vmss-${var.project}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.vm_size
  instances           = var.instance_count

  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.admin_ssh_public_key
  }

  # Conditional source_image: SIG version OR marketplace, never both
  source_image_id = var.use_custom_image ? data.azurerm_shared_image_version.selected[0].id : null

  dynamic "source_image_reference" {
    for_each = var.use_custom_image ? [] : [1]
    content {
      publisher = local.marketplace_publisher
      offer     = local.marketplace_offer
      sku       = local.marketplace_sku
      version   = local.marketplace_version
    }
  }

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  network_interface {
    name    = "nic-primary"
    primary = true

    ip_configuration {
      name      = "ipconfig-primary"
      primary   = true
      subnet_id = var.private_subnet_id
      load_balancer_backend_address_pool_ids = [
        var.backend_pool_override_id != null ? var.backend_pool_override_id : azurerm_lb_backend_address_pool.this.id
      ]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Cloud-init: only runs meaningfully when seed image is used.
  # When the custom image is in play, nginx is already installed and serving,
  # so this script is a no-op safety net.
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
    seed_mode = !var.use_custom_image
  }))

  upgrade_mode = "Automatic"

  automatic_instance_repair {
    enabled      = true
    grace_period = "PT10M"
  }

  tags = var.tags

  lifecycle {
    # instances is managed by autoscale (in prod) — don't fight with it
    ignore_changes = [instances]
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "autoscale-${var.project}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.this.id

  profile {
    name = "default"

    capacity {
      default = var.autoscale_default
      minimum = var.autoscale_min
      maximum = var.autoscale_max
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 75
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = var.tags
}

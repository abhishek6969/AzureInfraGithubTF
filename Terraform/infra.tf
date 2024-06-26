resource "azurerm_resource_group" "azureInfra" {
  name     = "azureInfra"
  location = "West Europe"
}

resource "azurerm_log_analytics_workspace" "test-law-lirook" {
  name                = "test-law-lirook"
  location            = azurerm_resource_group.azureInfra.location
  resource_group_name = azurerm_resource_group.azureInfra.name
  retention_in_days   = 30
}

resource "azurerm_monitor_data_collection_rule" "example" {
  name                = "example-dcr"
  resource_group_name = azurerm_resource_group.azureInfra.name
  location            = azurerm_resource_group.azureInfra.location

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.test-law-lirook.id
      name                  = azurerm_log_analytics_workspace.test-law-lirook.name
    }
  }

  data_sources {
    performance_counter {
      name                          = "example-perf-counter"
      streams                       = ["Microsoft-InsightsMetrics","Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "LogicalDisk(*)\\% Free Space",
        "Memory(*)\\% Available Memory",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\System\\System Up Time",
        "\\Memory\\% Committed Bytes In Use",



      ]
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics","Microsoft-Perf"]
    destinations = [azurerm_log_analytics_workspace.test-law-lirook.name]
  }

  description = "Data collection rule for performance counters"
}

resource "azurerm_automation_account" "lirookAutomation" {
  name                = "lirookAutomation"
  resource_group_name = azurerm_resource_group.azureInfra.name
  location            = azurerm_resource_group.azureInfra.location
  sku_name            = "Basic"
}


resource "azurerm_log_analytics_linked_service" "example" {
  resource_group_name = azurerm_resource_group.azureInfra.name
  workspace_id        = azurerm_log_analytics_workspace.test-law-lirook.id
  read_access_id      = azurerm_automation_account.lirookAutomation.id
}

resource "azurerm_maintenance_configuration" "test-MC2" {
  in_guest_user_patch_mode = "User"
  location                 = azurerm_resource_group.azureInfra.location
  name                     = "itops-montly_week2_3amist"
  resource_group_name      = azurerm_resource_group.azureInfra.name
  scope                    = "InGuestPatch"
  install_patches {
    reboot = "Always"
    linux {
      classifications_to_include = ["Critical", "Security", "Other"]
    }
    windows {
      classifications_to_include = ["Critical", "Security", "UpdateRollup", "FeaturePack", "ServicePack", "Definition", "Tools", "Updates"]
    }
  }
  window {
    duration        = "03:55"
    recur_every     = "1Month Second Tuesday Offset4"
    start_date_time = "2024-07-13 03:00"
    time_zone       = "India Standard Time"
  }
}

resource "azurerm_maintenance_assignment_dynamic_scope" "lirookDS" {
  name                         = "LirookDS"
  maintenance_configuration_id = azurerm_maintenance_configuration.test-MC2.id

  filter {
    tag_filter      = "Any"
    resource_types  = ["Microsoft.Compute/virtualMachines"]
    tags {
      tag    = "Maintainance_Window"
      values = ["Week2_Saturday_3-11AM_IST"]
    }
  }
}


resource "azurerm_recovery_services_vault" "lirrokVault" {
  name                = "lirrokVault"
  location            = azurerm_resource_group.azureInfra.location
  resource_group_name = azurerm_resource_group.azureInfra.name
  sku                 = "Standard"
  storage_mode_type = "LocallyRedundant"

  soft_delete_enabled = true
}

resource "azurerm_backup_policy_vm" "lirookRSVpolicy" {
  name                = "lirookRSVpolicy"
  resource_group_name = azurerm_resource_group.azureInfra.name
  recovery_vault_name = azurerm_recovery_services_vault.lirrokVault.name

  timezone = "India Standard Time"

  backup {
    frequency = "Daily"
    time      = "23:00"
  }

  retention_daily {
    count = 10
  }

}

resource "azurerm_log_analytics_solution" "example" {
  solution_name         = "ChangeTracking"
  location              = azurerm_resource_group.azureInfra.location
  resource_group_name   = azurerm_resource_group.azureInfra.name
  workspace_name = azurerm_log_analytics_workspace.test-law-lirook.name
  workspace_resource_id = azurerm_log_analytics_workspace.test-law-lirook.id
  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ChangeTracking"
  }
  depends_on = [ 
    azurerm_log_analytics_linked_service.example
  ]
}

resource "azurerm_automation_hybrid_runbook_worker_group" "lirook-workers" {
  for_each = var.worker_groups
  name                    = each.value.name
  resource_group_name     = azurerm_resource_group.azureInfra.name
  automation_account_name = azurerm_automation_account.lirookAutomation.name
}


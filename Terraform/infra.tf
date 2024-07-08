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
    azure_monitor_metrics {
      name = "azureMonitorMetrics-default"
    }
  }

  data_sources {
    performance_counter {
      name                          = "perfCounterDataSource60"
      streams                       = ["Microsoft-Perf", "Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\LogicalDisk(*)\\% Free Space",
        "Memory(*)\\% Available Memory",
        "\\Processor Information(_Total)\\% Processor Time",
        "\\System\\System Up Time",
        "\\Memory\\% Committed Bytes In Use",

      ]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf"]
    destinations = [azurerm_log_analytics_workspace.test-law-lirook.name]
    transform_kql = "source"
    output_stream = "Microsoft-Perf"
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["azureMonitorMetrics-default"]
    transform_kql = "source"
    output_stream = "Microsoft-InsightsMetrics"
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
resource "azurerm_monitor_data_collection_rule" "dcr-CT" {
  name                = "dcr-CT"
  resource_group_name = azurerm_resource_group.azureInfra.name
  location            = azurerm_resource_group.azureInfra.location

  data_sources {
    extension {
      name           = "CTDataSource-Windows"
      extension_name = "ChangeTracking-Windows"
      streams = [
        "Microsoft-ConfigurationChange",
        "Microsoft-ConfigurationChangeV2",
        "Microsoft-ConfigurationData"
      ]
      # Default CT configuration for Windows
      extension_json = <<JSON
        {
          "enableFiles": true,
          "enableSoftware": true,
          "enableRegistry": true,
          "enableServices": true,
          "enableInventory": true,
          "registrySettings": {
            "registryCollectionFrequency": 3000,
            "registryInfo": [
              {
                "name": "Registry_1",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\Scripts\\Startup",
                "valueName": ""
              },
              {
                "name": "Registry_2",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Group Policy\\Scripts\\Shutdown",
                "valueName": ""
              },
              {
                "name": "Registry_3",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Run",
                "valueName": ""
              },
              {
                "name": "Registry_4",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components",
                "valueName": ""
              },
              {
                "name": "Registry_5",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\ShellEx\\ContextMenuHandlers",
                "valueName": ""
              },
              {
                "name": "Registry_6",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\Background\\ShellEx\\ContextMenuHandlers",
                "valueName": ""
              },
              {
                "name": "Registry_7",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Classes\\Directory\\Shellex\\CopyHookHandlers",
                "valueName": ""
              },
              {
                "name": "Registry_8",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers",
                "valueName": ""
              },
              {
                "name": "Registry_9",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Explorer\\ShellIconOverlayIdentifiers",
                "valueName": ""
              },
              {
                "name": "Registry_10",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Browser Helper Objects",
                "valueName": ""
              },
              {
                "name": "Registry_11",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Browser Helper Objects",
                "valueName": ""
              },
              {
                "name": "Registry_12",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Internet Explorer\\Extensions",
                "valueName": ""
              },
              {
                "name": "Registry_13",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Internet Explorer\\Extensions",
                "valueName": ""
              },
              {
                "name": "Registry_14",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Drivers32",
                "valueName": ""
              },
              {
                "name": "Registry_15",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\Software\\Wow6432Node\\Microsoft\\Windows NT\\CurrentVersion\\Drivers32",
                "valueName": ""
              },
              {
                "name": "Registry_16",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Session Manager\\KnownDlls",
                "valueName": ""
              },
              {
                "name": "Registry_17",
                "groupTag": "Recommended",
                "enabled": false,
                "recurse": true,
                "description": "",
                "keyName": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Winlogon\\Notify",
                "valueName": ""
              }
            ]
          },
          "fileSettings": {
            "fileCollectionFrequency": 2700
          },
          "softwareSettings": {
            "softwareCollectionFrequency": 1800
          },
          "inventorySettings": {
            "inventoryCollectionFrequency": 36000
          },
          "servicesSettings": {
            "serviceCollectionFrequency": 1800
          }
        }
      JSON
    }
    extension {
      name           = "CTDataSource-Linux"
      extension_name = "ChangeTracking-Linux"
      streams = [
        "Microsoft-ConfigurationChange",
        "Microsoft-ConfigurationChangeV2",
        "Microsoft-ConfigurationData"
      ]
      # Default CT configuration for Linux
      extension_json = <<JSON
        {
          "enableFiles": true,
          "enableSoftware": true,
          "enableRegistry": false,
          "enableServices": true,
          "enableInventory": true,
          "fileSettings": {
            "fileCollectionFrequency": 900,
            "fileInfo": [
              {
                "name": "ChangeTrackingLinuxPath_default",
                "enabled": true,
                "destinationPath": "/etc/.*.conf",
                "useSudo": true,
                "recurse": true,
                "maxContentsReturnable": 5000000,
                "pathType": "File",
                "type": "File",
                "links": "Follow",
                "maxOutputSize": 500000,
                "groupTag": "Recommended"
              }
            ]
          },
          "softwareSettings": {
            "softwareCollectionFrequency": 300
          },
          "inventorySettings": {
            "inventoryCollectionFrequency": 36000
          },
          "servicesSettings": {
            "serviceCollectionFrequency": 300
          }
        }
      JSON
    }
  }

  data_flow {
    streams = [
      "Microsoft-ConfigurationChange",
      "Microsoft-ConfigurationChangeV2",
      "Microsoft-ConfigurationData"
    ]
    destinations = [
      "Microsoft-CT-Dest"
    ]
  }

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.test-law-lirook.id
      name                  = "Microsoft-CT-Dest"
    }
  }
  depends_on = [
    azurerm_log_analytics_linked_service.example,
    azurerm_log_analytics_solution.example
  ]
}
resource "azurerm_automation_runbook" "example" {
  name                    = "Get-ServerLastPatchDate"
  location                = azurerm_resource_group.azureInfra.location
  resource_group_name     = azurerm_resource_group.azureInfra.name
  automation_account_name = azurerm_automation_account.lirookAutomation.name
  log_verbose             = "true"
  log_progress            = "true"
  description             = "This runbook gets the date when the server was last patched."
  runbook_type            = "PowerShell"

  content = <<-EOT
  # Get the name of the local machine
  $ComputerName = $env:COMPUTERNAME

  # Get all installed updates
  $hotfixes = Get-HotFix -ComputerName $ComputerName

  # Filter for critical and security updates
  $criticalSecurityHotfixes = $hotfixes | Where-Object {
      $_.Description -match "Security Update" -or
      $_.Description -match "Critical Update"
  }

  # Sort by installation date and get the latest one
  $lastPatch = $criticalSecurityHotfixes | Sort-Object -Property InstalledOn | Select-Object -Last 1

  if ($lastPatch) {
      Write-Output "The last critical or security patch on $ComputerName was installed on: $($lastPatch.InstalledOn)"
  } else {
      Write-Output "No critical or security patches found on $ComputerName."
  }
  EOT
}

resource "azurerm_monitor_action_group" "LirookAG" {
  name                = "LirookAG"
  resource_group_name = azurerm_resource_group.azureInfra.name
  short_name = "LirookAG"
  email_receiver {
    name = "lirook-email-reciever"
    email_address = "lirooksunkale@outlook.com"
  }

}

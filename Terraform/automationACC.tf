resource "azurerm_automation_account" "lirookAutomation" {
  name                = "lirookAutomation"
  resource_group_name ="azureInfra"
  location            = "West Europe"
  sku_name            = "Basic"
}

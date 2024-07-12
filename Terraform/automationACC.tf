resource "azurerm_automation_account" "lirookAutomation" {
  name                = "lirookAutomation"
  resource_group_name =azurerm_resource_group.azureInfra.name
  location            = azurerm_resource_group.azureInfra.location
  sku_name            = "Basic"
}

resource "azurerm_resource_group" "azureInfra" {
  name     = "azureInfra"
  location = "West Europe"
}

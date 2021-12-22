resource "azurerm_eventhub_namespace" "evhns_telemetry_pipeline" {
  name                = "jrctest-azuretelemetry-pipeline"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Premium"
  zone_redundant      = true
  lifecycle {
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/6929
    ignore_changes = [capacity]
  }
}

resource "azurerm_eventhub" "evh_telemetry_pipeline" {
  for_each            = local.categories
  name                = "evh-${each.key}"
  namespace_name      = azurerm_eventhub_namespace.evhns_telemetry_pipeline.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
  partition_count     = each.value.eventhub_partitions
  message_retention   = each.value.eventhub_retention
}
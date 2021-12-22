data "archive_file" "function_zip" {
  source_dir  = "${path.module}/functions"
  output_path = "${path.module}/${local.build_string}-log_pipeline_function.zip"
  type        = "zip"
}

data "azurerm_storage_account" "log_source" {
  name                = var.log_source_sa
  resource_group_name = var.log_source_rg
}

data "azurerm_client_config" "current" {}

data "azurerm_eventhub_authorization_rule" "RootManageSharedAccessKey" {
  depends_on = [
    azurerm_eventhub.evh_telemetry_pipeline
  ]
  for_each            = azurerm_eventhub.evh_telemetry_pipeline
  name                = "${azurerm_eventhub_namespace.evhns_telemetry_pipeline.name}/RootManageSharedAccessKey"
  namespace_name      = azurerm_eventhub_namespace.evhns_telemetry_pipeline.name
  eventhub_name       = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
}
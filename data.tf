data "archive_file" "function_zip" {
  source_dir  = "${path.module}/functions"
  output_path = "${path.module}/${local.build_string}-log_pipeline_function.zip"
  type        = "zip"
}

/*
data "azurerm_function_app" "log_pipeline_function_app_data" {
  # this is a hack so that we can access the function app identity block elsewhere
  # since the azure terraform provider doesn't compute it when the resource is generated
  name                = azurerm_function_app.log_pipeline_function_app.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
}
*/

data "azurerm_storage_account" "log_source" {
  name                = var.log_source_sa
  resource_group_name = var.log_source_rg
}

data "azurerm_client_config" "current" {}
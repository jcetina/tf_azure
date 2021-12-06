data "archive_file" "function_zip" {
  source_dir  = "${path.module}/log_pipeline_function"
  output_path = "${base64sha256(null_resource.python_dependencies.id)}-${base64sha256(null_resource.set_queue_name.id)}-log_pipeline_function.zip"
  type        = "zip"
}

data "azurerm_function_app" "log_pipeline_function_app_data" {
  # this is a hack so that we can access the function app identity block elsewhere
  # since the azure terraform provider doesn't compute it when the resource is generated
  name                = azurerm_function_app.log_pipeline_function_app.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
}

data "azurerm_client_config" "current" {}
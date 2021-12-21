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
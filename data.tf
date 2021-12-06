data "archive_file" "function_zip" {
  source_dir  = "${path.module}/log_pipeline_function"
  output_path = "${base64sha256(null_resource.python_dependencies.id)}-log_pipeline_function.zip"
  type        = "zip"
}

data "azurerm_client_config" "current" {}
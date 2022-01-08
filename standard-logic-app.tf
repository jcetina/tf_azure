resource "azurerm_storage_account" "storage" {
  name                     = "azaudfoologicappst"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
  name                  = "logic-st-container"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "logic_blob" {
  # update the name in order to cause the function app to load a different blob on code changes
  name                   = local.logic_app_blob_name
  storage_account_name   = azurerm_storage_account.storage.name
  storage_container_name = azurerm_storage_container.container.name
  type                   = "Block"
  source                 = data.archive_file.logic_app.output_path
  # content_md5 changes force blob regeneration
  content_md5 = filemd5(data.archive_file.logic_app.output_path)
}

resource "azurerm_app_service_plan" "plan" {
  name                = "${var.prefix}-logic-app-sandbox-plan"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  location            = azurerm_resource_group.log_pipeline.location

  kind = "Windows"

  lifecycle {
    ignore_changes = [
      kind
    ]
  }

  sku {
    tier = "WorkflowStandard"
    size = "WS1"
  }
}

data "archive_file" "logic_app" {
  source_dir  = "${path.module}/logic-apps"
  output_path = "${path.module}/logic-apps.zip"
  type        = "zip"
}

resource "azurerm_logic_app_standard" "send_to_splunk" {
  name                       = local.send_to_splunk_logic_app_name
  resource_group_name        = azurerm_resource_group.log_pipeline.name
  location                   = azurerm_resource_group.log_pipeline.location
  app_service_plan_id        = azurerm_app_service_plan.plan.id
  storage_account_name       = azurerm_storage_account.storage.name
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  version                    = "~3"

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"                = "node"
    "WEBSITE_NODE_DEFAULT_VERSION"            = "~12"
    "WEBSITE_RUN_FROM_PACKAGE"                = azurerm_storage_blob.logic_blob.url
    "SpilloverBlobConnector_connectionString" = azurerm_storage_account.storage.primary_connection_string
    "TriggerIntervalMinutes"                  = 5
    "TriggerMessageCount"                     = 1000
    "SplunkHecUrl"                            = var.splunk_endpoint
    "SplunkHecToken"                          = var.hec_token_value
    "EventQueueConnApiId"                     = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.log_pipeline.location}/managedApis/azurequeues"
    "EventQueueConnectionId"                  = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.log_pipeline.name}/providers/Microsoft.Web/connections/azurequeues"
    "EventQueueConnectionKey"                 = azurerm_storage_account.storage.primary_access_key
    "EventQueueName"                          = azurerm_storage_queue.queues[local.event_output_queue].name
    "BatchWorkflowId"                         = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.log_pipeline.name}/providers/Microsoft.Web/sites/${local.send_to_splunk_logic_app_name}/workflows/BatchToSplunk"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "logic_reader" {
  scope                = azurerm_storage_account.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_logic_app_standard.send_to_splunk.identity.0.principal_id
}
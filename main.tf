
resource "azurerm_resource_group" "log_pipeline" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_storage_account" "log_pipeline" {
  name                     = "${replace(format("%s%s", var.prefix, random_string.log_storage_account.result), "/[^a-z0-9]/", "")}logst"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_eventgrid_system_topic" "log_pipeline" {
  name                   = "${var.prefix}-evgt"
  resource_group_name    = data.azurerm_storage_account.log_source.resource_group_name
  location               = azurerm_resource_group.log_pipeline.location
  source_arm_resource_id = data.azurerm_storage_account.log_source.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

}

resource "azurerm_eventgrid_system_topic_event_subscription" "log_pipeline" {
  name                          = "${var.prefix}-evgs"
  system_topic                  = azurerm_eventgrid_system_topic.log_pipeline.name
  resource_group_name           = data.azurerm_storage_account.log_source.resource_group_name
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.topics["${var.prefix}-event-input-sbt"].id
  included_event_types          = ["Microsoft.Storage.BlobCreated"]
}

resource "azurerm_servicebus_namespace" "log_pipeline" {
  name                = "${var.prefix}-sbn"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Standard"

}

resource "azurerm_servicebus_topic" "topics" {
  for_each            = toset(["${var.prefix}-event-input-sbt", "${var.prefix}-event-output-sbt"])
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name


  enable_partitioning = true
}

resource "azurerm_servicebus_queue" "queues" {
  for_each            = toset(["${var.prefix}-event-input-sbq", "${var.prefix}-event-output-sbq"])
  name                = "${var.prefix}-sbq"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning                  = true
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "shadow_queues" {
  for_each            = toset(["${var.prefix}-event-input-shadow-sbq", "${var.prefix}-event-output-shadow-sbq"])
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning = true
}

resource "azurerm_servicebus_subscription" "subs" {
  foreach = {
    "${var.prefix}-event-input-sbt"  = "${var.prefix}-event-input-sbq"
    "${var.prefix}-event-output-sbt" = "${var.prefix}-event-output-sbq"
  }
  name                = "${var.prefix}-event-input-sbs"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.topics[each.key].name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.queues[each.value].name
}

resource "azurerm_servicebus_subscription" "shadow_subs" {
  foreach = {
    "${var.prefix}-event-input-sbt"  = "${var.prefix}-event-input-shadow-sbq"
    "${var.prefix}-event-output-sbt" = "${var.prefix}-event-output-shadow-sbq"
  }
  name                = "${var.prefix}-event-input-shadow-sbs"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.topics[each.key].name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.queues[each.value].name
}


resource "azurerm_storage_account" "log_pipeline_function_app_storage" {
  name                     = "${replace(format("%s%s", var.prefix, random_string.func_storage_account.result), "/[^a-z0-9]/", "")}funcst"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "log_pipeline_function_app_storage_container" {
  name                  = "${var.prefix}-func-st-container"
  storage_account_name  = azurerm_storage_account.log_pipeline_function_app_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "func_app_storage_blob" {
  # update the name in order to cause the function app to load a different blob on code changes
  name                   = "${var.prefix}-func-code-${filemd5(data.archive_file.function_zip.output_path)}.zip"
  storage_account_name   = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_container_name = azurerm_storage_container.log_pipeline_function_app_storage_container.name
  type                   = "Block"
  source                 = data.archive_file.function_zip.output_path
  # content_md5 changes force blob regeneration
  content_md5 = filemd5(data.archive_file.function_zip.output_path)
}

resource "azurerm_app_service_plan" "log_pipeline_function_app_plan" {
  name                = "${var.prefix}-plan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Standard"
    size = "S1"
  }
}

resource "azurerm_application_insights" "log_pipeline_function_application_insights" {
  name                = "${var.prefix}-appi"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  application_type    = "other"
}

resource "azurerm_function_app" "log_pipeline_function_app" {
  name                       = "${var.prefix}-func"
  location                   = azurerm_resource_group.log_pipeline.location
  resource_group_name        = azurerm_resource_group.log_pipeline.name
  app_service_plan_id        = azurerm_app_service_plan.log_pipeline_function_app_plan.id
  storage_account_name       = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_account_access_key = azurerm_storage_account.log_pipeline_function_app_storage.primary_access_key
  enable_builtin_logging     = false

  app_settings = {
    "AzureServiceBusConnectionString" = azurerm_servicebus_namespace.log_pipeline.default_primary_connection_string,
    "AzureWebJobsStorage"             = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string,
    # WEBSITE_RUN_FROM_PACKAGE url will update any time the code changes because the blob name includes the md5 of the code zip file
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.log_pipeline_function_app_storage.name}.blob.core.windows.net/${azurerm_storage_container.log_pipeline_function_app_storage_container.name}/${azurerm_storage_blob.func_app_storage_blob.name}",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.log_pipeline_function_application_insights.instrumentation_key,
    "HEC_TOKEN_SECRET_NAME"          = var.hec_token_name,
    "VAULT_URI"                      = azurerm_key_vault.log_pipeline_vault.vault_uri,
  }

  identity {
    type = "SystemAssigned"
  }



  os_type = "linux"
  version = "~3"

  site_config {
    linux_fx_version          = "PYTHON|3.8"
    use_32_bit_worker_process = false
    always_on                 = false
  }
}

resource "azurerm_role_assignment" "func_reader" {
  scope                = azurerm_storage_account.log_pipeline_function_app_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id
}

resource "azurerm_role_assignment" "log_reader" {
  scope                = data.azurerm_storage_account.log_source.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id
}

resource "azurerm_role_assignment" "service_bus_sender" {
  scope                = azurerm_servicebus_topic.log_pipeline.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id
}

resource "azurerm_key_vault" "log_pipeline_vault" {
  name                = "${var.prefix}-kv"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "premium"

}


resource "azurerm_key_vault_access_policy" "function_app_read_policy" {
  key_vault_id = azurerm_key_vault.log_pipeline_vault.id

  tenant_id = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.tenant_id
  object_id = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id

  secret_permissions = [
    "get",
    "list"
  ]
}

resource "azurerm_key_vault_access_policy" "key_setter_policy" {
  key_vault_id = azurerm_key_vault.log_pipeline_vault.id

  tenant_id = data.azurerm_client_config.current.tenant_id
  object_id = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "set",
    "get",
    "delete",
    "purge",
    "recover"
  ]
}

resource "azurerm_key_vault_secret" "hec_token" {
  name         = var.hec_token_name
  value        = var.hec_token_value
  key_vault_id = azurerm_key_vault.log_pipeline_vault.id
  depends_on = [
    azurerm_key_vault_access_policy.key_setter_policy
  ]
}


resource "null_resource" "python_dependencies" {
  triggers = {
    build_number = uuid()
  }
  provisioner "local-exec" {
    command = "pip install --target=${path.module}/functions/.python_packages/lib/site-packages -r ${path.module}/functions/requirements.txt"
  }
}

resource "null_resource" "set_input_queue_name" {
  triggers = {
    build_number = uuid()
  }
  provisioner "local-exec" {
    command = "sed -i 's/STORAGE_RECEIVER_INPUT_QUEUE/${azurerm_servicebus_queue.queues["${var.prefix}-event-input-sbq"].name}/g' ${path.module}/functions/StorageEventReceiver/function.json"
  }
}

resource "null_resource" "set_output_queue_name" {
  triggers = {
    build_number = uuid()
  }
  provisioner "local-exec" {
    command = "sed -i 's/STORAGE_RECEIVER_OUTPUT_QUEUE/${azurerm_servicebus_queue.queues["${var.prefix}-event-output-sbq"].name}/g' ${path.module}/functions/StorageEventReceiver/function.json"
  }
}

resource "random_string" "log_storage_account" {
  length  = 8
  upper   = false
  special = false
}

resource "random_string" "func_storage_account" {
  length  = 8
  upper   = false
  special = false
}
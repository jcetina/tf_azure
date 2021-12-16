resource "azurerm_resource_group" "log_pipeline" {
  name     = "${var.prefix}-rg"
  location = var.location
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
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.topics[local.event_input_topic].id
  included_event_types          = ["Microsoft.Storage.BlobCreated"]
  subject_filter {
    subject_ends_with = ".avro"
  }
}

resource "azurerm_servicebus_namespace" "log_pipeline" {
  name                = "${var.prefix}-sbn"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Standard"

}

resource "azurerm_servicebus_topic" "topics" {
  for_each            = toset([local.event_input_topic])
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name


  enable_partitioning = true
}

resource "azurerm_servicebus_queue" "queues" {
  for_each = {
    (local.event_input_queue) = {
      dead_letter = true
    }
    (local.event_input_shadow_queue) = {
      dead_letter = false
    }
  }
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning                  = true
  dead_lettering_on_message_expiration = each.value.dead_letter
}

resource "azurerm_servicebus_subscription" "subs" {
  for_each = {
    "${var.prefix}-event-input-sbs-main" = {
      from = local.event_input_topic
      to   = local.event_input_queue
    }
    "${var.prefix}-event-input-sbs-shadow" = {
      from = local.event_input_topic
      to   = local.event_input_shadow_queue
    }
  }
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.topics[each.value.from].name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.queues[each.value.to].name
}

/*
resource "azurerm_storage_account" "log_pipeline_function_app_storage" {
  name                     = replace(format("%s%s%s", var.prefix, random_string.func_storage_account.result, var.func_storage_account_suffix), "/[^a-z0-9]/", "")
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
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

resource "azurerm_storage_queue" "queues" {
  for_each             = toset([local.event_output_queue])
  name                 = each.key
  storage_account_name = azurerm_storage_account.log_pipeline_function_app_storage.name
}

resource "azurerm_app_service_plan" "log_pipeline_function_app_plan" {
  name                = "${var.prefix}-plan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Standard"
    size = "S3"
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
    "StorageAccountConnectionString" = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string,
  }

  identity {
    type = "SystemAssigned"
  }

  os_type = "linux"
  version = "~3"

  site_config {
    linux_fx_version          = "PYTHON|3.8"
    use_32_bit_worker_process = false
    always_on                 = true
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

  # this is needed so that the deploying account can set vault secrets
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
*/

resource "azurerm_key_vault_secret" "hec_token" {
  name         = var.hec_token_name
  value        = var.hec_token_value
  key_vault_id = azurerm_key_vault.log_pipeline_vault.id
  depends_on = [
    azurerm_key_vault_access_policy.key_setter_policy
  ]
}


resource "azurerm_logic_app_workflow" "message_batch_workflow" {
  name                = "${var.prefix}-logic"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
}

resource "azurerm_logic_app_trigger_custom" "batch_trigger" {
  name         = "${var.prefix}-logic-trigger"
  logic_app_id = azurerm_logic_app_workflow.message_batch_workflow.id

  body = <<BODY
{
  "inputs": {
    "configurations": {
      "msg1kOrFreq5m": {
        "releaseCriteria": {
          "messageCount": 3,
           "recurrence": {
             "frequency": "Minute",
             "interval": 5
            }
          }
        }
      },
      "mode": "Inline"
    },
  "type": "Batch"
}
BODY

}

resource "azurerm_logic_app_action_custom" "init_output" {
  name         = "init_output"
  logic_app_id = azurerm_logic_app_workflow.message_batch_workflow.id

  body = <<BODY
{
  "inputs": {
    "variables": [
          {
              "name": "output",
              "type": "string"
          }
      ]
  },
  "runAfter": {},
  "type": "InitializeVariable"
}
BODY

}

resource "azurerm_logic_app_action_custom" "for_each" {
  name         = "for_each"
  logic_app_id = azurerm_logic_app_workflow.message_batch_workflow.id

  depends_on = [
    azurerm_logic_app_action_custom.init_output
  ]
  body = <<BODY
{
  "actions": {
      "Compose": {
          "inputs": "@join(items('for_each')['content'], '\\n')",
          "runAfter": {},
          "type": "Compose"
      },
      "Set_variable": {
          "inputs": {
              "name": "output",
              "value": "@{outputs('Compose')}"
          },
          "runAfter": {
              "Compose": [
                  "Succeeded"
              ]
          },
          "type": "SetVariable"
      }
  },
  "foreach": "@triggerBody()['items']",
  "runAfter": {
      "init_output": [
          "Succeeded"
      ]
  },
  "runtimeConfiguration": {
      "concurrency": {
          "repetitions": 1
      }
  },
  "type": "Foreach"
}
BODY

}

resource "azurerm_logic_app_action_custom" "to_splunk" {
  name         = "to_splunk"
  logic_app_id = azurerm_logic_app_workflow.message_batch_workflow.id

  depends_on = [
    azurerm_logic_app_action_custom.for_each
  ]
  body = <<BODY
{
    "inputs": {
        "body": "@variables('output')",
        "headers": {
            "Authorization": "Splunk ${var.hec_token_value}"
        },
        "method": "POST",
        "uri": "https://splunk.mattuebel.com/services/collector/raw?channel=49b42560-9fde-40f6-8c9b-32e0d81be1e2&sourcetype=test"
    },
    "runAfter": {
      "for_each": [
        "Succeeded"
      ]
    },
    "type": "Http"
}
BODY
}

/*
resource "azurerm_resource_group_template_deployment" "queue_sender_logic" {
  name                = "queue_sender_logic"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  deployment_mode     = "Incremental"
  parameters_content = jsonencode({
    "workflows_queue_sender_name" = {
      value = "${var.prefix}-sender-logic"
    }
    "source_queue_name" = {
      value = azurerm_storage_queue.queues[local.event_output_queue].name
    }
    "workflows_queue_receiver_externalid" = {
      value = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.log_pipeline.name}/providers/Microsoft.Logic/workflows/${azurerm_logic_app_workflow.message_batch_workflow.name}"
    }
    "connections_queues_name" = {
      value = "queue-connector"
    }
  })
  template_content = file("${path.module}/queue_sender_logic_app_arm.json")
}
*/

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
    command = "sed -i 's/STORAGE_RECEIVER_INPUT_QUEUE/${azurerm_servicebus_queue.queues[local.event_input_queue].name}/g' ${path.module}/functions/StorageEventReceiver/function.json"
  }
  depends_on = [
    null_resource.set_output_queue_name
  ]
}

resource "null_resource" "set_output_queue_name" {
  triggers = {
    build_number = uuid()
  }
  provisioner "local-exec" {
    command = "sed -i 's/STORAGE_RECEIVER_OUTPUT_QUEUE/${azurerm_storage_queue.queues[local.event_output_queue].name}/g' ${path.module}/functions/StorageEventReceiver/function.json"
  }
}

resource "random_string" "func_storage_account" {
  length  = 24 - length(replace(format("%s%s", var.prefix, var.func_storage_account_suffix), "/[^a-z0-9]/", ""))
  upper   = false
  special = false
}

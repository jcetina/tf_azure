resource "azurerm_resource_group" "log_pipeline" {
  name     = "${var.prefix}-rg"
  location = var.location
}

resource "azurerm_eventgrid_system_topic" "storage_topic" {
  name                   = "${var.prefix}-evgt"
  resource_group_name    = data.azurerm_storage_account.log_source.resource_group_name
  location               = azurerm_resource_group.log_pipeline.location
  source_arm_resource_id = data.azurerm_storage_account.log_source.id
  topic_type             = "Microsoft.Storage.StorageAccounts"
}

resource "azurerm_eventgrid_system_topic_event_subscription" "blob_created" {
  name                          = "${var.prefix}-evgs"
  system_topic                  = azurerm_eventgrid_system_topic.storage_topic.name
  resource_group_name           = data.azurerm_storage_account.log_source.resource_group_name
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.topics[local.event_input_topic].id
  included_event_types          = ["Microsoft.Storage.BlobCreated"]
  subject_filter {
    subject_ends_with = ".avro"
  }
}

resource "azurerm_servicebus_namespace" "blob_pubsub" {
  name                = "${var.prefix}-sbn"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Standard"

}

resource "azurerm_servicebus_topic" "topics" {
  for_each            = toset([local.event_input_topic])
  name                = each.key
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.blob_pubsub.name


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
  namespace_name      = azurerm_servicebus_namespace.blob_pubsub.name

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
  namespace_name      = azurerm_servicebus_namespace.blob_pubsub.name
  topic_name          = azurerm_servicebus_topic.topics[each.value.from].name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.queues[each.value.to].name
}


resource "azurerm_storage_account" "function_app_storage" {
  name                     = replace(format("%s%s%s", var.prefix, random_string.func_storage_account.result, var.func_storage_account_suffix), "/[^a-z0-9]/", "")
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "function_app_storage_container" {
  name                  = "${var.prefix}-func-st-container"
  storage_account_name  = azurerm_storage_account.function_app_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "func_app_storage_blob" {
  # update the name in order to cause the function app to load a different blob on code changes
  name                   = local.func_app_blob_name
  storage_account_name   = azurerm_storage_account.function_app_storage.name
  storage_container_name = azurerm_storage_container.function_app_storage_container.name
  type                   = "Block"
  source                 = data.archive_file.function_zip.output_path
  # content_md5 changes force blob regeneration
  content_md5 = filemd5(data.archive_file.function_zip.output_path)
}

resource "azurerm_storage_account" "queue_storage" {
  name                     = replace(format("%s%s%s", var.prefix, random_string.queue_storage_account.result, var.queue_storage_account_suffix), "/[^a-z0-9]/", "")
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_queue" "queues" {
  for_each             = toset([local.event_output_queue])
  name                 = each.key
  storage_account_name = azurerm_storage_account.queue_storage.name
}


resource "azurerm_app_service_plan" "function_app_plan" {
  name                = "${var.prefix}-plan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Premium"
    size = "P1v3"
  }
}

resource "azurerm_application_insights" "function_app_insights" {
  name                = "${var.prefix}-appi"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  application_type    = "other"
}

resource "azurerm_function_app" "function_app" {
  name                       = "${var.prefix}-func"
  location                   = azurerm_resource_group.log_pipeline.location
  resource_group_name        = azurerm_resource_group.log_pipeline.name
  app_service_plan_id        = azurerm_app_service_plan.function_app_plan.id
  storage_account_name       = azurerm_storage_account.function_app_storage.name
  storage_account_access_key = azurerm_storage_account.function_app_storage.primary_access_key
  enable_builtin_logging     = false

  app_settings = {
    "AzureServiceBusConnectionString" = azurerm_servicebus_namespace.blob_pubsub.default_primary_connection_string,
    "AzureWebJobsStorage"             = azurerm_storage_account.function_app_storage.primary_connection_string,
    # WEBSITE_RUN_FROM_PACKAGE url will update any time the code changes because the blob name includes the md5 of the code zip file
    "WEBSITE_RUN_FROM_PACKAGE"       = azurerm_storage_blob.func_app_storage_blob.url
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.function_app_insights.instrumentation_key,
    "StorageAccountConnectionString" = azurerm_storage_account.function_app_storage.primary_connection_string,
    "INPUT_QUEUE_NAME"               = azurerm_servicebus_queue.queues[local.event_input_queue].name,
    "OUTPUT_QUEUE_NAME"              = azurerm_storage_queue.queues[local.event_output_queue].name,
  }

  identity {
    type = "SystemAssigned"
  }

  os_type = "linux"
  version = "~3"

  site_config {
    linux_fx_version = "PYTHON|3.8"
    always_on        = true
  }
}


resource "azurerm_role_assignment" "func_reader" {
  scope                = azurerm_storage_account.function_app_storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_function_app.function_app.identity.0.principal_id
}

resource "azurerm_role_assignment" "log_reader" {
  scope                = data.azurerm_storage_account.log_source.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_function_app.function_app.identity.0.principal_id
}

resource "azurerm_resource_group_template_deployment" "queue_connector" {
  name                = "queue_connector_deployment"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  deployment_mode     = "Incremental"
  parameters_content = jsonencode({
    "connections_queues_name" = {
      value = local.queue_connector_name
    }
    "storage_account_name" = {
      value = azurerm_storage_account.function_app_storage.name
    }
    "storage_access_key" = {
      value = azurerm_storage_account.function_app_storage.primary_access_key
    }
  })
  template_content = file("${path.module}/queue_connector_arm.json")
}

resource "azurerm_resource_group_template_deployment" "queue_sender_logic" {
  name                = "${var.prefix}-queue-sender-logic-deployment"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  deployment_mode     = "Incremental"
  depends_on = [
    azurerm_resource_group_template_deployment.batch_receiver_logic
  ]
  parameters_content = jsonencode({
    "workflows_queue_sender_name" = {
      value = "${var.prefix}-sender-logic"
    }
    "source_queue_name" = {
      value = azurerm_storage_queue.queues[local.event_output_queue].name
    }
    "workflows_queue_receiver_externalid" = {
      value = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_resource_group.log_pipeline.name}/providers/Microsoft.Logic/workflows/${local.batch_receiver_logic_app_name}"
    }
    "workflows_queue_receiver_trigger_name" = {
      value = local.batch_trigger_name
    }
    "workflows_queue_receiver_batch_name" = {
      value = local.batch_name
    }
    "connections_queues_name" = {
      value = local.queue_connector_name
    }
  })
  template_content = file("${path.module}/queue_sender_logic_app_arm.json")
}

resource "azurerm_resource_group_template_deployment" "batch_receiver_logic" {
  name                = "${var.prefix}-batch-receiver-logic-deployment"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  deployment_mode     = "Incremental"
  /*
  "workflows_batch_receiver_logic_name": {
            "type": "String"
        },
        "connections_blob_name": {
            "type": "String"
        },
        "workflows_batch_receiver_trigger_name": {
            "type": "String"
        },
        "workflows_batch_receiver_batch_name": {
            "type": "String"
        },
        "spillover_container": {
            "type": "String"
        },
        "hec_token": {
            "type": "String"
        },
        "batch_size": {
            "type": "Int",
            "defaultValue": 1000
        },
        "batch_interval_minutes": {
            "type": "Int",
            "defaultValue": 5
        }
  */
  parameters_content = jsonencode({
    "workflows_batch_receiver_logic_name" = {
      value = local.batch_receiver_logic_app_name
    }
    "connections_blob_name" = {
      value = local.blob_connector_name
    }
    "workflows_batch_receiver_trigger_name" = {
      value = local.batch_trigger_name
    }
    "workflows_batch_receiver_batch_name" = {
      value = local.batch_name
    }
    "spillover_container" = {
      value = azurerm_storage_container.spillover_container.name
    }
    "hec_token" = {
      value = var.hec_token_value
    }
    "batch_size" = {
      value = local.batch_size
    }
    "batch_interval_minutes" = {
      value = local.batch_interval_minutes
    }
  })
  template_content = file("${path.module}/batch_receiver_logic_app_arm.json")
}



resource "null_resource" "python_dependencies" {
  triggers = {
    build_number = uuid()
  }
  provisioner "local-exec" {
    command = "pip install --target=${path.module}/functions/.python_packages/lib/site-packages -r ${path.module}/functions/requirements.txt"
  }
}

resource "azurerm_storage_account" "splunk_spillover_storage" {
  name                     = "jrctestspillover"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "spillover_container" {
  name                  = "spillover"
  storage_account_name  = azurerm_storage_account.splunk_spillover_storage.name
  container_access_type = "private"
}

resource "azurerm_resource_group_template_deployment" "blob_connector" {
  name                = "${var.prefix}-blob-connector"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  deployment_mode     = "Incremental"
  parameters_content = jsonencode({
    "connections_azureblob_name" = {
      value = local.blob_connector_name
    }
    "storage_account_name" = {
      value = azurerm_storage_account.splunk_spillover_storage.name
    }
    "storage_access_key" = {
      value = azurerm_storage_account.splunk_spillover_storage.primary_access_key
    }
  })
  template_content = file("${path.root}/blob_connector_arm.json")
}

resource "random_string" "func_storage_account" {
  length  = 24 - length(replace(format("%s%s", var.prefix, var.func_storage_account_suffix), "/[^a-z0-9]/", ""))
  upper   = false
  special = false
}

resource "random_string" "queue_storage_account" {
  length  = 24 - length(replace(format("%s%s", var.prefix, var.queue_storage_account_suffix), "/[^a-z0-9]/", ""))
  upper   = false
  special = false
}
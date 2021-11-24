# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }
  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "log_pipeline" {
  name     = "LogPipelineResourceGroup"
  location = "eastus"

}


resource "azurerm_storage_account" "log_pipeline" {
  name                     = "cooldiagnosticlogs"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_eventgrid_system_topic" "log_pipeline" {
  name                   = "CoolDiagnosticLogsSubscriptionTopic"
  resource_group_name    = azurerm_resource_group.log_pipeline.name
  location               = azurerm_resource_group.log_pipeline.location
  source_arm_resource_id = azurerm_storage_account.log_pipeline.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

}

resource "azurerm_eventgrid_system_topic_event_subscription" "log_pipeline" {
  name                          = "LogPipelineEventSubscription"
  system_topic                  = azurerm_eventgrid_system_topic.log_pipeline.name
  resource_group_name           = azurerm_resource_group.log_pipeline.name
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.log_pipeline.id
  included_event_types          = ["Microsoft.Storage.BlobCreated"]
}

resource "azurerm_servicebus_namespace" "log_pipeline" {
  name                = "LogPipelineServiceBusNamespace"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Standard"

}

resource "azurerm_servicebus_topic" "log_pipeline" {
  name                = "LogPipelineServiceBusTopic"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name


  enable_partitioning = true
}

resource "azurerm_servicebus_queue" "log_pipeline" {
  name                = "LogPipelineServiceBusQueue"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning                  = true
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_subscription" "log_pipeline" {
  name                = "LogPipelineServiceBusSubcription"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.log_pipeline.name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.log_pipeline.name
}


resource "azurerm_storage_account" "log_pipeline_function_app_storage" {
  name                     = "logfunctionappstorage"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "log_pipeline_function_app_storage_container" {
  name                  = "log-pipeline-app-storage-container"
  storage_account_name  = azurerm_storage_account.log_pipeline_function_app_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "log_pipeline_storage_blob" {
  name                   = "log_pipeline_function.zip"
  storage_account_name   = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_container_name = azurerm_storage_container.log_pipeline_function_app_storage_container.name
  type                   = "Block"
  source                 = data.archive_file.log_pipeline_function.output_path
}
resource "azurerm_app_service_plan" "log_pipeline_function_app_plan" {
  name                = "LogPipelineFunctionAppServicePlan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_application_insights" "log_pipeline_function_application_insights" {
  name                = "LogPipelineFunctionApplicationInsights"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  application_type    = "other"
}

resource "azurerm_function_app" "log_pipeline_function_app" {
  name                       = "LogPipelineFunction"
  location                   = azurerm_resource_group.log_pipeline.location
  resource_group_name        = azurerm_resource_group.log_pipeline.name
  app_service_plan_id        = azurerm_app_service_plan.log_pipeline_function_app_plan.id
  storage_account_name       = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_account_access_key = azurerm_storage_account.log_pipeline_function_app_storage.primary_access_key


  app_settings = {
    "AzureWebJobsAzureSBConnection"  = azurerm_servicebus_namespace.log_pipeline.default_primary_connection_string,
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.log_pipeline_function_app_storage.name}.blob.core.windows.net/${azurerm_storage_container.log_pipeline_function_app_storage_container.name}/${azurerm_storage_blob.log_pipeline_storage_blob.name}${data.azurerm_storage_account_blob_container_sas.storage_account_blob_container_token.sas}",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.log_pipeline_function_application_insights.instrumentation_key,
  }


  os_type = "linux"
  version = "~3"
  site_config {
    linux_fx_version          = "PYTHON|3.7"
    use_32_bit_worker_process = false
  }

}

data "archive_file" "log_pipeline_function" {
  type        = "zip"
  source_dir  = "${path.module}/log_pipeline_function"
  output_path = "log_pipeline_function.zip"
}

data "azurerm_storage_account_blob_container_sas" "storage_account_blob_container_token" {
  connection_string = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string
  container_name    = azurerm_storage_container.log_pipeline_function_app_storage_container.name
  # start and expirty could probably be locals later
  start  = timeadd(timestamp(), "-4h")
  expiry = timeadd(timestamp(), "4h")

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

/*
locals {
  az_login_command     = "az login --service-principal -u $ARM_CLIENT_ID -p $ARM_CLIENT_SECRET --tenant $ARM_TENANT_ID"
  publish_code_command = "az webapp deployment source config-zip --resource-group ${azurerm_resource_group.log_pipeline.name} --name ${azurerm_function_app.log_pipeline_function_app.name} --src ${data.archive_file.log_pipeline_function.output_path}"
}


resource "null_resource" "az_login" {
  provisioner "local-exec" {
    command = local.az_login_command
  }
  depends_on = [local.az_login_command]
  triggers = {
    input_json           = filemd5(data.archive_file.log_pipeline_function.output_path)
    publish_code_command = local.publish_code_command
  }
}

resource "null_resource" "function_app_publish" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }
  depends_on = [local.publish_code_command, null_resource.az_login]
  triggers = {
    input_json           = filemd5(data.archive_file.log_pipeline_function.output_path)
    publish_code_command = local.publish_code_command
  }
}
*/
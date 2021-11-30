# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }
  required_version = ">= 0.14.9"


  backend "remote" {
    organization = "cetinas-dot-org"

    workspaces {
      name = "tf_azure"
    }
  }

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

resource "azurerm_servicebus_queue" "log_pipeline_shadow_queue" {
  name                = "LogPipelineServiceBusShadowQueue"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning = true
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

resource "azurerm_servicebus_subscription" "log_pipeline_shadow_subscription" {
  name                = "LogPipelineServiceBusShadowSubcription"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.log_pipeline.name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.log_pipeline_shadow_queue.name
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
  content_md5            = filemd5("log_pipeline_function.zip")
}
resource "azurerm_app_service_plan" "log_pipeline_function_app_plan" {
  name                = "LogPipelineFunctionAppServicePlan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "FunctionApp"
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
    "AzureServiceBusConnectionString" = azurerm_servicebus_namespace.log_pipeline.default_primary_connection_string,
    "AzureWebJobsStorage"             = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string,
    # "WEBSITE_RUN_FROM_PACKAGE"        = "https://${azurerm_storage_account.log_pipeline_function_app_storage.name}.blob.core.windows.net/${azurerm_storage_container.log_pipeline_function_app_storage_container.name}/${azurerm_storage_blob.log_pipeline_storage_blob.name}${data.azurerm_storage_account_blob_container_sas.storage_account_blob_container_token.sas}",
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.log_pipeline_function_app_storage.name}.blob.core.windows.net/${azurerm_storage_container.log_pipeline_function_app_storage_container.name}/${azurerm_storage_blob.log_pipeline_storage_blob.name}",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.log_pipeline_function_application_insights.instrumentation_key,
  }

  identity {
    type = "SystemAssigned"
  }

  os_type = "linux"
  version = "~3"
  site_config {
    use_32_bit_worker_process = false
  }

}


resource "azurerm_role_assignment" "log_pipeline_blob_reader" {
  scope                = azurerm_resource_group.log_pipeline.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id
}

data "azurerm_function_app" "log_pipeline_function_app_data" {
  name                = azurerm_function_app.log_pipeline_function_app.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
  depends_on = [
    azurerm_function_app.log_pipeline_function_app
  ]
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
  start  = "2021-11-23T00:00:00Z"
  expiry = "2022-11-23T00:00:00Z"

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
resource "azurerm_user_assigned_identity" "log_pipeline_function_app_identity" {
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  name                = "log-pipeline-app"
}

*/
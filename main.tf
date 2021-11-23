# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }

    time_provider = {
      source  = "hashicorp/time"
      version = "~> 0.7.2"
    }

  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

provider "time_provider" {
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

resource "azurerm_app_service_plan" "log_pipeline_function_app_plan" {
  name                = "LogPipelineFunctionAppServicePlan"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  kind                = "FunctionApp"

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


  os_type = "linux"
  version = "~3"
  site_config {
    use_32_bit_worker_process = false
  }

}

resource "time_static" "now" {}

data "azurerm_storage_account_blob_container_sas" "storage_account_blob_container_sas" {
  connection_string = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string
  container_name    = azurerm_storage_container.log_pipeline_function_app_storage_container.name

  start  = time_static.now.rfc3339
  expiry = timeadd(time_static.now.rfc3339, "4h")

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

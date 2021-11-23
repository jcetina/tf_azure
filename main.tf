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
  name                = "LogPipelineEventSubscription"
  system_topic        = azurerm_eventgrid_system_topic.log_pipeline.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.log_pipeline.id
  included_event_types   = ["Microsoft.Storage.BlobCreated"]
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

  enable_partitioning = true
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
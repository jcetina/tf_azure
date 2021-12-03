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

variable "location" {
  type    = string
  default = "eastus"
}

variable "hec_token_name" {
  type    = string
  default = "hec-token"
}

variable "hec_token_value" {
  type      = string
  sensitive = true
}

variable "vault_name" {
  type    = string
  default = "logpipelinevault3"
}

resource "azurerm_resource_group" "log_pipeline" {
  name     = "LogPipelineResourceGroup2"
  location = var.location
}

resource "azurerm_storage_account" "log_pipeline" {
  name                     = "cooldiagnosticlogs2"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_eventgrid_system_topic" "log_pipeline" {
  name                   = "CoolDiagnosticLogsSubscriptionTopic2"
  resource_group_name    = azurerm_resource_group.log_pipeline.name
  location               = azurerm_resource_group.log_pipeline.location
  source_arm_resource_id = azurerm_storage_account.log_pipeline.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

}

resource "azurerm_eventgrid_system_topic_event_subscription" "log_pipeline" {
  name                          = "LogPipelineEventSubscription2"
  system_topic                  = azurerm_eventgrid_system_topic.log_pipeline.name
  resource_group_name           = azurerm_resource_group.log_pipeline.name
  service_bus_topic_endpoint_id = azurerm_servicebus_topic.log_pipeline.id
  included_event_types          = ["Microsoft.Storage.BlobCreated"]
}

resource "azurerm_servicebus_namespace" "log_pipeline" {
  name                = "LogPipelineServiceBusNamespace2"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  sku                 = "Standard"

}

resource "azurerm_servicebus_topic" "log_pipeline" {
  name                = "LogPipelineServiceBusTopic2"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name


  enable_partitioning = true
}

resource "azurerm_servicebus_queue" "log_pipeline" {
  name                = "LogPipelineServiceBusQueue2"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning                  = true
  dead_lettering_on_message_expiration = true
}

resource "azurerm_servicebus_queue" "log_pipeline_shadow_queue" {
  name                = "LogPipelineServiceBusShadowQueue2"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name

  enable_partitioning = true
}

resource "azurerm_servicebus_subscription" "log_pipeline" {
  name                = "LogPipelineServiceBusSubcription2"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.log_pipeline.name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.log_pipeline.name
}

resource "azurerm_servicebus_subscription" "log_pipeline_shadow_subscription" {
  name                = "LogPipelineServiceBusShadowSubcription2"
  resource_group_name = azurerm_resource_group.log_pipeline.name
  namespace_name      = azurerm_servicebus_namespace.log_pipeline.name
  topic_name          = azurerm_servicebus_topic.log_pipeline.name

  max_delivery_count  = 10
  default_message_ttl = "P14D"
  forward_to          = azurerm_servicebus_queue.log_pipeline_shadow_queue.name
}


resource "azurerm_storage_account" "log_pipeline_function_app_storage" {
  name                     = "logfunctionappstorage2"
  resource_group_name      = azurerm_resource_group.log_pipeline.name
  location                 = azurerm_resource_group.log_pipeline.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "log_pipeline_function_app_storage_container" {
  name                  = "log-pipeline-app-storage-container-2"
  storage_account_name  = azurerm_storage_account.log_pipeline_function_app_storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "log_pipeline_storage_blob" {
  # update the name in order to cause the function app to load a different blob on code changes
  name                   = "log_pipeline_function-${filemd5(local.output_path)}.zip"
  storage_account_name   = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_container_name = azurerm_storage_container.log_pipeline_function_app_storage_container.name
  type                   = "Block"
  source                 = local.output_path
  # content_md5 changes force blob regeneration
  content_md5 = filemd5(local.output_path)
  depends_on = [
    null_resource.zip_folder
  ]
}

resource "azurerm_app_service_plan" "log_pipeline_function_app_plan_two" {
  name                = "LogPipelineFunctionAppServicePlan3"
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
  name                = "LogPipelineFunctionApplicationInsights2"
  location            = azurerm_resource_group.log_pipeline.location
  resource_group_name = azurerm_resource_group.log_pipeline.name
  application_type    = "other"
}

resource "azurerm_function_app" "log_pipeline_function_app" {
  name                       = "LogPipelineFunctionApp2"
  location                   = azurerm_resource_group.log_pipeline.location
  resource_group_name        = azurerm_resource_group.log_pipeline.name
  app_service_plan_id        = azurerm_app_service_plan.log_pipeline_function_app_plan_two.id
  storage_account_name       = azurerm_storage_account.log_pipeline_function_app_storage.name
  storage_account_access_key = azurerm_storage_account.log_pipeline_function_app_storage.primary_access_key

  app_settings = {
    "AzureServiceBusConnectionString" = azurerm_servicebus_namespace.log_pipeline.default_primary_connection_string,
    "AzureWebJobsStorage"             = azurerm_storage_account.log_pipeline_function_app_storage.primary_connection_string,
    # WEBSITE_RUN_FROM_PACKAGE url will update any time the code changes because the blob name includes the md5 of the code zip file
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.log_pipeline_function_app_storage.name}.blob.core.windows.net/${azurerm_storage_container.log_pipeline_function_app_storage_container.name}/${azurerm_storage_blob.log_pipeline_storage_blob.name}",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.log_pipeline_function_application_insights.instrumentation_key,
    "HEC_TOKEN_SECRET_NAME"          = var.hec_token_name,
    "HEC_VAULT_URI"                  = azurerm_key_vault.log_pipeline_vault.vault_uri,
  }

  identity {
    type = "SystemAssigned"
  }

  os_type = "linux"
  version = "~3"

  site_config {
    linux_fx_version          = "PYTHON|3.8"
    use_32_bit_worker_process = false
  }
}

resource "azurerm_role_assignment" "log_pipeline_blob_reader" {
  scope                = azurerm_resource_group.log_pipeline.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = data.azurerm_function_app.log_pipeline_function_app_data.identity.0.principal_id
}

resource "azurerm_key_vault" "log_pipeline_vault" {
  name                = var.vault_name
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
    build_number = base64sha256(timestamp())
  }
  provisioner "local-exec" {
    command = "pip install --target=${path.module}/log_pipeline_function/.python_packages/lib/site-packages -r ${path.module}/log_pipeline_function/requirements.txt"
  }
}

resource "null_resource" "zip_folder" {
  triggers = {
    build_number = base64sha256(timestamp())
  }
  provisioner "local-exec" {
    command = "zip -r ${path.module}/log_pipeline_function.zip ${local.source_dir}"
  }
  depends_on = [
    null_resource.python_dependencies
  ]
}

data "azurerm_function_app" "log_pipeline_function_app_data" {
  # this is a hack so that we can access the function app identity block elsewhere
  # since the azure terraform provider doesn't compute it when the resource is generated
  name                = azurerm_function_app.log_pipeline_function_app.name
  resource_group_name = azurerm_resource_group.log_pipeline.name
}

locals {
  # https://stackoverflow.com/questions/40744575/how-to-run-command-before-data-archive-file-zips-folder-in-terraform
  # this forces waiting for python dependencies to install
  python_dependencies_id = null_resource.python_dependencies.id

  # this forces the zip file below to wait on this resource, which waits on the python deps
  source_dir  = "${path.module}/log_pipeline_function"
  output_path = "${path.module}/log_pipeline_function.zip"
}


data "azurerm_client_config" "current" {}
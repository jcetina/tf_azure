output "telemetry_event_hubs" {
  value = tomap({
    for k, v in azurerm_eventhub.evh_telemetry_pipeline : k => {
      "id"                            = v.id
      "default_authorization_rule_id" = data.azurerm_eventhub_authorization_rule.RootManageSharedAccessKey[k].id
    }
  })
}
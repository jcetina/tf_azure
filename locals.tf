locals {
  # build_string = sha256("${null_resource.set_input_queue_name.id}-${null_resource.set_output_queue_name.id}-${null_resource.python_dependencies.id}")
  build_string = sha256(null_resource.python_dependencies.id)

  event_input_topic = "${var.prefix}-event-input-sbt"


  event_input_queue = "${var.prefix}-event-input-sbq"

  event_output_queue = "${var.prefix}-event-output-stq"

  event_input_shadow_queue = "${var.prefix}-event-input-shadow-sbq"

  batch_name = "SplunkHecBatch"

  func_app_blob_name = "${var.prefix}-func-code-${filemd5(data.archive_file.function_zip.output_path)}.zip"

  categories = {
    activitylogs = {
      eventhub_partitions = 4
      eventhub_retention  = 7
    }
  }

  batch_receiver_logic_app_name = "${var.prefix}-batch-receiver"

  blob_connector_name = "${var.prefix}-blob-connector"

  queue_connector_name = "${var.prefix}-queue-connector"

  batch_trigger_name = "${var.prefix}-batch-trigger"

  batch_size = 1000

  batch_interval_minutes = 5
}
locals {
  build_string = sha256("${null_resource.set_input_queue_name.id}-${null_resource.set_output_queue_name.id}-${null_resource.python_dependencies.id}")

  event_input_topic = "${var.prefix}-event-input-sbt"


  event_input_queue = "${var.prefix}-event-input-sbq"

  event_output_queue = "${var.prefix}-event-output-stq"

  event_input_shadow_queue = "${var.prefix}-event-input-shadow-sbq"

  batch_name = "msg1kOrFreq5m"

  func_app_blob_name = "${var.prefix}-func-code-${filemd5(data.archive_file.function_zip.output_path)}.zip"

  categories = {
    activitylogs = {
      eventhub_partitions = 4
      eventhub_retention  = 7
    }
  }

}
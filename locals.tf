locals {
  build_string = sha256("${null_resource.set_input_queue_name.id}-${null_resource.set_output_queue_name.id}-${null_resource.python_dependencies.id}")

  event_input_topic         = "${var.prefix}-event-input-sbt"
  event_output_topic        = "${var.prefix}-event-output-sbt"
  event_input_queue         = "${var.prefix}-event-input-sbq"
  event_output_queue        = "${var.prefix}-event-output-sbq"
  event_input_shadow_queue  = "${var.prefix}-event-input-shadow-sbq"
  event_output_shadow_queue = "${var.prefix}-event-output-shadow-sbq"
}
locals {
  build_string = sha256("${null_resource.set_input_queue_name.id}-${null_resource.set_output_queue_name.id}-${null_resource.python_dependencies.id}")
}
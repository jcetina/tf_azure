
variable "prefix" {
  description = "The prefix used for all resources in this project."
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "log_source_rg" {
  type = string
}

variable "log_source_sa" {
  type = string
}

variable "hec_token_name" {
  type    = string
  default = "hec-token"
}

variable "hec_token_value" {
  type      = string
  sensitive = true
}

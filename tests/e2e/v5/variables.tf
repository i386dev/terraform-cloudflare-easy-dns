variable "zone_id" {
  description = "Cloudflare Zone ID of the test zone"
  type        = string
}

variable "zone_name" {
  description = "Domain name of the test zone"
  type        = string
}

variable "prefix" {
  description = "Label of this run"
  type        = string
}

variable "a_value" {
  description = "IPv4 address of the record without a key"
  type        = string
  default     = "192.0.2.10"
}

variable "txt_value" {
  description = "Value of the TXT record with a key"
  type        = string
  default     = "rotation=1"
}

variable "report_unmanaged" {
  description = "Report the records of the zone that the configuration does not describe"
  type        = bool
  default     = false
}

output "unmanaged_records" {
  description = "Records of the zone that the configuration does not describe"
  value       = module.dns.unmanaged_records
  sensitive   = true
}

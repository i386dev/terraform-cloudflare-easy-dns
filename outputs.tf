output "record_names" {
  description = "Names of all managed records"
  value       = module.v5.record_names
}

output "records" {
  description = "Managed records keyed by their stable identifier, with id, name, type and content"
  value       = module.v5.records
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = module.v5.state_migration
}

output "import_ids" {
  description = "Import IDs (<zone_id>/<record_id>) of records that already exist in the zone, keyed by record key. Empty unless import_existing is true; records with no match are left out, and ambiguous matches stop the plan"
  value       = module.v5.import_ids
}

output "import_duplicates" {
  description = "Cloudflare record IDs of existing records that a configured record cannot be matched to unambiguously, keyed by record key. Empty unless import_existing is true; while there are any, the plan stops with this list"
  value       = module.v5.import_duplicates
}

output "unmanaged_records" {
  description = "Records in the zone that the configuration does not describe (id, name, type, content, data). Empty unless report_unmanaged is true. Sensitive: the content of a proxied record is the origin address that Cloudflare hides"
  value       = module.v5.unmanaged_records
  sensitive   = true
}

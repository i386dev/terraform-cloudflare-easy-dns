output "import_ids" {
  description = "Records found in the zone and imported"
  value       = module.dns.import_ids
}

output "import_duplicates" {
  description = "Records that cannot be imported unambiguously (the plan stops while there are any)"
  value       = module.dns.import_duplicates
}

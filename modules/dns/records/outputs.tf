output "flat_records" {
  description = "Flattened map of records keyed by \"<name> <TYPE> <value>\", ready for for_each"
  value       = local.flat_records

  precondition {
    condition     = length(local.duplicates) == 0
    error_message = "Duplicate records (remove the duplicates or set a unique key for each of them; MX records that differ only in priority and CAA records that differ only in flags have the same key and need a key too):\n${join("\n", local.duplicates)}"
  }

  precondition {
    condition     = length(local.low_ttls) == 0
    error_message = "TTLs below ${var.minimum_ttl} seconds are only available on the Cloudflare Enterprise plan. If this zone is on Enterprise, set minimum_ttl = 30 in the module call; otherwise use a TTL of at least 60 seconds, or 1 for automatic:\n${join("\n", local.low_ttls)}"
  }

  precondition {
    condition     = length(local.misplaced_wildcards) == 0
    error_message = "A wildcard must be the whole leftmost label of a name (\"*\", \"*.app\"); these names put it elsewhere:\n${join("\n", local.misplaced_wildcards)}"
  }

  precondition {
    condition     = length(local.long_names) == 0
    error_message = "A fully qualified name can have at most 253 characters; these names (prefix, name and zone together) are longer:\n${join("\n", local.long_names)}"
  }

  precondition {
    condition     = length(local.self_cnames) == 0
    error_message = "A CNAME (or alias) cannot point to its own name:\n${join("\n", local.self_cnames)}"
  }

  precondition {
    condition     = length(local.cname_conflicts) == 0
    error_message = "A CNAME record cannot share its name with other records (except at the zone apex), and a name has at most one CNAME. Names that already have a CNAME next to other records in the zone can be listed in allowed_cname_conflicts:\n${join("\n", local.cname_conflicts)}"
  }
}

output "state_migration" {
  description = "Map of record keys used by module versions 1.x to the current keys, for state migration"
  value       = local.state_migration
}

output "import_record_ids" {
  description = "Cloudflare record IDs of existing_records matching the configured records, keyed by record key. Records with no or several matches are left out"
  value       = local.import_record_ids
}

output "import_duplicates" {
  description = "Cloudflare record IDs of existing_records that match the same configured record, keyed by record key. These records are not imported"
  value       = local.import_duplicates
}

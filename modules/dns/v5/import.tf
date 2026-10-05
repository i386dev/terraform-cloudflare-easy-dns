# Lookup of records that already exist in the zone: the record types of the
# configuration for var.import_existing, all record types for var.report_unmanaged.
# Matching to the configured records is done in the records module.

locals {
  # Record types of the configuration (ALIASES are CNAMEs)
  import_types = toset(flatten([
    for base_name, type_map in var.records : [
      for raw_key, recs in type_map :
      replace(element(split(".", raw_key), length(split(".", raw_key)) - 1), "ALIASES", "CNAME")
    ]
  ]))

  # Record types that cloudflare_dns_record manages
  all_types = ["A", "AAAA", "CAA", "CERT", "CNAME", "DNSKEY", "DS", "HTTPS", "LOC", "MX", "NAPTR", "NS", "OPENPGPKEY", "PTR", "SMIMEA", "SRV", "SSHFP", "SVCB", "TLSA", "TXT", "URI"]

  lookup_types = setunion(
    var.import_existing ? local.import_types : toset([]),
    var.report_unmanaged ? toset(local.all_types) : toset([]),
  )
}

# One lookup per record type: the provider returns data.flags as a number for CAA and
# DNSKEY and as null for other types, and a list mixing both makes Terraform crash.
# Can be a single lookup once https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004 is fixed
data "cloudflare_dns_records" "existing" {
  for_each = local.lookup_types

  zone_id   = var.zone_id
  type      = each.key
  max_items = local.import_max_items

  lifecycle {
    # Records beyond the limit are not found, so they would be planned as new records
    # (and fail with "record already exists" at apply) or missing from the report of
    # unmanaged records; the plan stops instead
    postcondition {
      condition     = length(self.result) < local.import_max_items
      error_message = "The lookup of existing ${each.key} records returned ${local.import_max_items} records (the limit), so records beyond it would not be found: with import_existing they would be planned as new, with report_unmanaged they would be missing from the report. Set both to false and import or review these records on your own."
    }
  }
}

locals {
  # Records read per type; a lookup that returns this many was probably cut off
  import_max_items = 10000

  existing_records = flatten([
    for type, lookup in data.cloudflare_dns_records.existing : [
      for r in lookup.result : {
        id      = r.id
        name    = r.name
        type    = r.type
        content = r.content
        # MX and URI only: the API may return a priority for other types as well
        priority = contains(["MX", "URI"], r.type) ? r.priority : null
        data     = r.data == null ? null : { for field, value in r.data : field => tostring(value) if value != null }
      }
    ]
  ])
}

# The report of records that the configuration does not describe: a warning only, the
# module never deletes records it does not manage. The warning has no record values:
# the content of a proxied record is the origin address that Cloudflare hides, and
# plans often end up in CI logs
locals {
  # Type, name and ID of each unmanaged record, for the warning; the values stay in the
  # sensitive output
  unmanaged_summary = var.report_unmanaged ? [for r in nonsensitive(module.records.unmanaged_records) : "${r.type} ${r.name} (${r.id})"] : []

  # Configured records that match several records in the zone (copies, or a record that
  # is described too loosely): with import_existing they stop the plan, without it the
  # report lists them
  ambiguous_summary = var.import_existing || !var.report_unmanaged ? [] : distinct([for m in values(nonsensitive(module.records.ambiguous_matches)) : "${m.type} ${m.name}: ${join(", ", m.ids)}"])

  unmanaged_message = length(local.unmanaged_summary) == 0 ? "" : "The zone has ${length(local.unmanaged_summary)} records that the configuration does not describe (records of other tools, such as external-dns, are listed too). Add them to records and adopt them with import blocks (import_existing gives their IDs), or delete them yourself. Their values are in the sensitive unmanaged_records output: pass it through as a root module output, then terraform plan -out=tfplan and terraform show -json tfplan:\n${join("\n", slice(local.unmanaged_summary, 0, min(50, length(local.unmanaged_summary))))}${length(local.unmanaged_summary) > 50 ? "\n... and ${length(local.unmanaged_summary) - 50} more" : ""}"
  ambiguous_message = length(local.ambiguous_summary) == 0 ? "" : "Configured records that match several records in the zone: copies of one record, which only one record can describe (remove the extra copies), or records that the configuration describes too loosely (for example, a structured record without a field that tells it apart; set that field):\n${join("\n", slice(local.ambiguous_summary, 0, min(50, length(local.ambiguous_summary))))}${length(local.ambiguous_summary) > 50 ? "\n... and ${length(local.ambiguous_summary) - 50} more" : ""}"
}

check "unmanaged_records" {
  assert {
    condition     = !var.report_unmanaged || length(local.unmanaged_summary) + length(local.ambiguous_summary) == 0
    error_message = join("\n\n", compact([local.unmanaged_message, local.ambiguous_message]))
  }
}


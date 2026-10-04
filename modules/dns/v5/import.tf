# Lookup of records that already exist in the zone, enabled by var.import_existing.
# Matching to the configured records is done in the records module.

locals {
  # Record types of the configuration (ALIASES are CNAMEs)
  import_types = toset(flatten([
    for base_name, type_map in var.records : [
      for raw_key, recs in type_map :
      replace(element(split(".", raw_key), length(split(".", raw_key)) - 1), "ALIASES", "CNAME")
    ]
  ]))
}

# One lookup per record type: the provider returns data.flags as a number for CAA and
# DNSKEY and as null for other types, and a list mixing both makes Terraform crash.
# Can be a single lookup once https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004 is fixed
data "cloudflare_dns_records" "existing" {
  for_each = var.import_existing ? local.import_types : toset([])

  zone_id   = var.zone_id
  type      = each.key
  max_items = local.import_max_items

  lifecycle {
    # Records beyond the limit are not found, so they would be planned as new records
    # and fail with "record already exists" at apply; the plan stops instead
    postcondition {
      condition     = length(self.result) < local.import_max_items
      error_message = "The lookup of existing ${each.key} records returned ${local.import_max_items} records (the limit), so records beyond it would not be found and would be planned as new. Set import_existing = false and import these records with import blocks of their own."
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

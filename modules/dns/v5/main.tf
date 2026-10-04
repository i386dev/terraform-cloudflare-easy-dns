locals {
  root_domain = coalesce(var.zone_name, try(data.cloudflare_zone.this[0].name, null))

  # Fields of data that hold text (the other fields are numbers or N/S, E/W)
  text_data_fields = ["certificate", "digest", "fingerprint", "public_key", "regex", "replacement", "service", "target", "value"]
}

module "records" {
  source = "../records"

  root_domain             = local.root_domain
  records                 = var.records
  existing_records        = local.existing_records
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = var.minimum_ttl
}

data "cloudflare_zone" "this" {
  count   = var.zone_name == null ? 1 : 0
  zone_id = var.zone_id

  lifecycle {
    # Cloudflare returns the name of an internationalized zone in Unicode, while
    # record names come back in Punycode
    postcondition {
      condition     = !can(regex("[^[:ascii:]]", self.name))
      error_message = "The zone ${jsonencode(self.name)} has an internationalized name, which Cloudflare returns in Unicode: set zone_name in Punycode (xn--mnchen-3ya.de for münchen.de)."
    }
  }
}

resource "cloudflare_dns_record" "record" {
  for_each = module.records.flat_records

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content

  ttl = each.value.proxied ? 1 : each.value.ttl

  # Records with structured data (CAA, SRV, ...) cannot be proxied
  proxied  = each.value.data == null ? each.value.proxied : null
  priority = each.value.priority
  comment  = each.value.comment
  tags     = length(each.value.tags) > 0 ? each.value.tags : null
  settings = each.value.settings

  # Numeric flags (CAA, DNSKEY) are sent as numbers, NAPTR flags as a string
  data = each.value.data == null ? null : {
    algorithm      = lookup(each.value.data, "algorithm", null)
    altitude       = lookup(each.value.data, "altitude", null)
    certificate    = lookup(each.value.data, "certificate", null)
    digest         = lookup(each.value.data, "digest", null)
    digest_type    = lookup(each.value.data, "digest_type", null)
    fingerprint    = lookup(each.value.data, "fingerprint", null)
    flags          = try(tonumber(each.value.data["flags"]), lookup(each.value.data, "flags", null))
    key_tag        = lookup(each.value.data, "key_tag", null)
    lat_degrees    = lookup(each.value.data, "lat_degrees", null)
    lat_direction  = lookup(each.value.data, "lat_direction", null)
    lat_minutes    = lookup(each.value.data, "lat_minutes", null)
    lat_seconds    = lookup(each.value.data, "lat_seconds", null)
    long_degrees   = lookup(each.value.data, "long_degrees", null)
    long_direction = lookup(each.value.data, "long_direction", null)
    long_minutes   = lookup(each.value.data, "long_minutes", null)
    long_seconds   = lookup(each.value.data, "long_seconds", null)
    matching_type  = lookup(each.value.data, "matching_type", null)
    order          = lookup(each.value.data, "order", null)
    port           = lookup(each.value.data, "port", null)
    precision_horz = lookup(each.value.data, "precision_horz", null)
    precision_vert = lookup(each.value.data, "precision_vert", null)
    preference     = lookup(each.value.data, "preference", null)
    priority       = lookup(each.value.data, "priority", null)
    protocol       = lookup(each.value.data, "protocol", null)
    public_key     = lookup(each.value.data, "public_key", null)
    regex          = lookup(each.value.data, "regex", null)
    replacement    = lookup(each.value.data, "replacement", null)
    selector       = lookup(each.value.data, "selector", null)
    service        = lookup(each.value.data, "service", null)
    size           = lookup(each.value.data, "size", null)
    tag            = lookup(each.value.data, "tag", null)
    target         = lookup(each.value.data, "target", null)
    type           = lookup(each.value.data, "type", null)
    usage          = lookup(each.value.data, "usage", null)
    value          = lookup(each.value.data, "value", null)
    weight         = lookup(each.value.data, "weight", null)
  }
}

# Numbers in text values are written in their canonical form ("0123" -> "123",
# "1.10" -> "1.1"), which loses what was written in YAML; quoting keeps it. The text
# fields of data are checked too (a hex digest of digits loses its leading zeros);
# numeric fields such as port or priority may be numbers
check "records_text_values_are_strings" {
  assert {
    condition = alltrue(flatten([
      for name, types in var.records : [
        for type, list in types : [
          for record in list : concat(
            # fine: a JSON string, or a value that is not a number
            [for attribute in ["content", "key", "comment", "tag"] : startswith(jsonencode(try(record[attribute], "")), "\"") || !can(tonumber(try(record[attribute], "")))],
            [for field in setintersection(try(keys(record.data), []), local.text_data_fields) : startswith(jsonencode(try(record.data[field], "")), "\"") || !can(tonumber(try(record.data[field], "")))],
            # tags may be a list or a set (a set has no index), so the values are iterated
            try([for tag in record.tags : startswith(jsonencode(tag), "\"") || !can(tonumber(tag))], []),
          )
        ]
      ]
    ]))
    error_message = "Text values given as numbers are written in their canonical form (0123 -> 123, 1.10 -> 1.1); in YAML quote them to keep them as written:\n${join("\n", flatten([
      for name, types in var.records : [
        for type, list in types : [
          for index, record in list : concat(
            [
              for attribute in ["content", "key", "comment", "tag"] : "records[\"${name}\"][\"${type}\"][${index}].${attribute} is ${jsonencode(record[attribute])}"
              if !startswith(jsonencode(try(record[attribute], "")), "\"") && can(tonumber(try(record[attribute], "")))
            ],
            [
              for field in setintersection(try(keys(record.data), []), local.text_data_fields) : "records[\"${name}\"][\"${type}\"][${index}].data.${field} is ${jsonencode(try(record.data[field], ""))}"
              if !startswith(jsonencode(try(record.data[field], "")), "\"") && can(tonumber(try(record.data[field], "")))
            ],
            [
              for tag in try([for tag in record.tags : tag], []) : "records[\"${name}\"][\"${type}\"][${index}].tags has ${jsonencode(tag)}"
              if !startswith(jsonencode(tag), "\"") && can(tonumber(tag))
            ],
          )
        ]
      ]
    ]))}"
  }
}

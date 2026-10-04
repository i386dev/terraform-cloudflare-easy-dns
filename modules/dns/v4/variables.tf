variable "zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}

variable "zone_name" {
  description = "Zone domain name (e.g. example.com). If null, it is looked up from zone_id. A trailing dot is ignored. Internationalized zones must set it, in Punycode"
  type        = string
  default     = null

  # Checked here: an empty name would otherwise fail in coalesce() with an unclear error.
  # A non-ASCII name gets its own error, since the DNS name rule does not say why it fails
  validation {
    condition     = var.zone_name == null || !can(regex("[^[:ascii:]]", var.zone_name))
    error_message = "zone_name must be in Punycode (xn--mnchen-3ya.de for münchen.de). An internationalized zone needs it set: Cloudflare returns the names of such zones in Unicode, so they cannot be looked up from zone_id."
  }

  validation {
    condition     = var.zone_name == null || can(regex("[^[:ascii:]]", var.zone_name)) || can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\\.?$", var.zone_name))
    error_message = "zone_name must be the DNS name of the zone, such as example.com (or null to look it up from zone_id)."
  }
}

variable "records" {
  description = <<-EOT
    DNS records: `records[NAME][TYPE] = [RECORD, ...]`, where NAME is a name within the
    zone (`@` for the apex) and TYPE a record type, optionally with a prefix
    (`"_acme-challenge.TXT"`). Record attributes: `content`, `ttl`, `proxied`, `priority`,
    `tag`, `flags`, `data`, `key`, `comment`, `tags` and `settings` (`flatten_cname`,
    `ipv4_only`, `ipv6_only`). See the README for the details. Unknown attributes fail at plan.
  EOT
  # Not a typed object: Terraform silently drops unknown attributes when converting to an
  # object type, so misspelled attributes are checked here and the typed structure is
  # built by the records module
  type = any

  validation {
    condition = try(alltrue(flatten([
      for name, types in var.records : [
        for type, list in types : [
          for record in list : (
            can(keys(record))
            && length(setsubtract(keys(record), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings"])) == 0
            && (try(record.settings, null) == null || length(setsubtract(try(keys(record.settings), ["?"]), ["flatten_cname", "ipv4_only", "ipv6_only"])) == 0)
          )
        ]
      ]
    ])), false)
    error_message = try(
      "Invalid records (allowed attributes: content, ttl, proxied, priority, tag, flags, data, key, comment, tags, settings):\n${join("\n", flatten([
        for name, types in var.records : [
          for type, list in types : [
            for index, record in list : concat(
              can(keys(record)) ? [] : ["records[\"${name}\"][\"${type}\"][${index}] must be an object"],
              [for attribute in setsubtract(try(keys(record), []), ["content", "ttl", "proxied", "priority", "tag", "flags", "data", "key", "comment", "tags", "settings"]) : "records[\"${name}\"][\"${type}\"][${index}]: unknown attribute \"${attribute}\""],
              [for attribute in setsubtract(try(keys(record.settings), []), ["flatten_cname", "ipv4_only", "ipv6_only"]) : "records[\"${name}\"][\"${type}\"][${index}].settings: unknown attribute \"${attribute}\""]
            )
          ]
        ]
      ]))}",
      "records must be a map of names to maps of record types to lists of records."
    )
  }
  # YAML 1.1 reads unquoted off/on/yes/no/N/Y as booleans, and Terraform would turn them
  # into "false"/"true" without an error; values that must be text cannot be booleans.
  # An unquoted N is accepted as a LOC lat_direction, where it can only mean north
  validation {
    condition = try(alltrue(flatten([
      for name, types in var.records : [
        for type, list in types : [
          for record in list : concat(
            [for attribute in ["content", "key", "comment", "tag"] : !contains(["true", "false"], jsonencode(try(record[attribute], "")))],
            [for field in try(keys(record.data), []) : !contains(["true", "false"], jsonencode(try(record.data[field], ""))) || (field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")],
            [for index in try(range(length(record.tags)), []) : !contains(["true", "false"], jsonencode(try(record.tags[index], "")))],
          )
        ]
      ]
    ])), true)
    error_message = try(
      "Text values must be strings, in YAML quote them (\"off\", \"yes\", \"N\"); unquoted they are read as booleans:\n${join("\n", flatten([
        for name, types in var.records : [
          for type, list in types : [
            for index, record in list : concat(
              [
                for attribute in ["content", "key", "comment", "tag"] : "records[\"${name}\"][\"${type}\"][${index}].${attribute} is ${jsonencode(record[attribute])}"
                if contains(["true", "false"], jsonencode(try(record[attribute], "")))
              ],
              [
                for field in try(keys(record.data), []) : "records[\"${name}\"][\"${type}\"][${index}].data.${field} is ${jsonencode(try(record.data[field], ""))}"
                if contains(["true", "false"], jsonencode(try(record.data[field], ""))) && !(field == "lat_direction" && jsonencode(try(record.data[field], "")) == "false")
              ],
              [
                for tag_index in try(range(length(record.tags)), []) : "records[\"${name}\"][\"${type}\"][${index}].tags[${tag_index}] is ${jsonencode(try(record.tags[tag_index], ""))}"
                if contains(["true", "false"], jsonencode(try(record.tags[tag_index], "")))
              ],
            )
          ]
        ]
      ]))}",
      "Text values must be strings."
    )
  }
}

variable "default_ttl" {
  description = "TTL of records that do not set one (1 means automatic)"
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = var.default_ttl == 1 || (var.default_ttl >= 30 && var.default_ttl <= 86400)
    error_message = "default_ttl must be 1 (automatic) or between 30 and 86400 seconds."
  }
}

variable "default_proxied" {
  description = "Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare"
  type        = bool
  default     = false
  nullable    = false
}

variable "default_comment" {
  description = "Comment of records that do not set one, e.g. \"Managed by Terraform\""
  type        = string
  default     = null
}

variable "default_tags" {
  description = "Tags added to all records, e.g. [\"managed-by:terraform\"] (tags require a Cloudflare plan that supports them)"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_cname_conflicts" {
  description = "Names where a CNAME already shares its name with other records in the zone, e.g. [\"community\", \"*.legacy.example.com\"]. Cloudflare accepts this for records that are not proxied, and older zones often have such names; only the listed names are exempt from the CNAME check. Compared fully qualified and case-insensitively; a second CNAME on a name still fails, and listed names without a conflict show a warning"
  type        = list(string)
  default     = []
  nullable    = false
}

variable "minimum_ttl" {
  description = "Lowest TTL other than 1 (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones: set 30 there, keep 60 otherwise"
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = contains([30, 60], var.minimum_ttl)
    error_message = "minimum_ttl must be 60, or 30 for zones on the Cloudflare Enterprise plan."
  }
}

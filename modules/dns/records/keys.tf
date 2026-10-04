# Resolved records and their keys. The key is the Terraform address of a record
# ("<name> <TYPE> <value>"), so it depends on the value or on an explicit key, never on
# the position in a list: reordering records changes nothing, and a record with a key is
# updated in place when its value changes.

locals {
  # Resolved records: ALIASES become CNAMEs, prefixes are prepended to the base name
  resolved = [
    for i, e in local.entries : {
      rec    = e.rec
      source = e.source
      name   = local.entry_names[i]
      type   = e.kind == "ALIASES" ? "CNAME" : e.kind
      # Alias targets are the fully qualified base name, so "app" and
      # "app.example.com" both point to app.example.com
      content = e.kind == "ALIASES" ? (e.prefix == null ? local.qualified[e.base_name] : "${e.prefix}.${local.qualified[e.base_name]}") : e.rec.content

      # Key used by module versions 1.x, for state migration
      old_key = (
        e.kind == "ALIASES" && e.prefix == null ? "ALIASES_${e.base_name}_${e.rec.content}" :
        e.kind == "ALIASES" ? "ALIASES_INLINE_${e.base_name}_${e.raw_key}_${e.idx}_${e.rec.content}" :
        e.raw_key == "CAA" ? "CAA_${e.base_name}_${e.rec.tag}_${e.rec.content}_${e.rec.flags}" :
        "${e.raw_key}_${e.base_name}_${e.idx}"
      )
    }
  ]

  # Canonical form of the configured IPv6 addresses (cidrhost formats them like
  # RFC 5952: lower case, no leading zeros, the longest run of zeros as ::). An
  # IPv4-mapped address would come back as IPv4, so it stays as written (in lower
  # case), like a value that is not an address (rejected by the validation)
  canonical_ipv6 = {
    for address in distinct([for r in local.resolved : r.content if r.type == "AAAA"]) : address => (
      strcontains(try(cidrhost("${address}/128", 0), ""), ":") ? cidrhost("${address}/128", 0) : lower(address)
    )
  }

  # Keys follow the zone file format: "<name> <TYPE> <value>"
  keyed = [
    for r in local.resolved : merge(r, {
      key = (
        r.rec.key != null ? "${r.name} ${r.type} ${r.rec.key}" :
        r.type == "CNAME" ? "${r.name} CNAME" :
        r.type == "CAA" ? "${r.name} CAA ${r.rec.tag} ${r.content}" :
        r.type == "TXT" ? "${r.name} TXT ${substr(sha1(r.content), 0, 12)}" :
        contains(local.data_types, r.type) ? "${r.name} ${r.type} ${substr(sha1(jsonencode(r.rec.data)), 0, 12)}" :
        "${r.name} ${r.type} ${r.content}"
      )
    })
  ]

  records = [
    for r in local.keyed : {
      key     = r.key
      old_key = r.old_key
      source  = r.source
      name    = r.name
      fqdn    = local.fqdn[r.name]
      # The key without its name part, normalized like DNS compares it: addresses
      # and hostnames case-insensitively and without a trailing dot, IPv6 addresses
      # in their canonical form (2001:0db8:0:0:0:0:0:1 is 2001:db8::1)
      key_value = (
        r.rec.key == null && contains(["A", "AAAA", "MX", "NS", "PTR"], r.type)
        ? "${r.type} ${r.type == "AAAA" ? local.canonical_ipv6[r.content] : lower(trimsuffix(r.content, "."))}"
        : trimprefix(r.key, "${r.name} ")
      )
      type = r.type
      # IPv6 addresses are sent in the canonical form, as Cloudflare stores them; the
      # key keeps the address as written
      content = r.type == "CAA" || contains(local.data_types, r.type) ? null : r.type == "AAAA" ? local.canonical_ipv6[r.content] : r.content
      ttl     = coalesce(r.rec.ttl, var.default_ttl)
      proxied = (
        r.rec.proxied != null ? r.rec.proxied :
        contains(["A", "AAAA", "CNAME"], r.type) ? var.default_proxied :
        false
      )
      comment  = r.rec.comment != null ? r.rec.comment : var.default_comment
      tags     = distinct(concat(var.default_tags, coalesce(r.rec.tags, [])))
      settings = r.rec.settings
      priority = contains(["MX", "URI"], r.type) ? r.rec.priority : r.type == "SRV" ? tonumber(r.rec.data.priority) : null
      data = (
        r.type == "CAA" ? tomap({ flags = tostring(r.rec.flags), tag = r.rec.tag, value = r.content }) :
        # Cloudflare returns SVCB and HTTPS targets as fully qualified names, so they
        # get the trailing dot here to avoid a diff on every plan
        contains(["HTTPS", "SVCB"], r.type) ? merge(r.rec.data, {
          target = endswith(r.rec.data.target, ".") ? r.rec.data.target : "${r.rec.data.target}."
        }) :
        # yamldecode reads an unquoted N as false (YAML 1.1); for LOC it can only mean north
        r.type == "LOC" ? merge(r.rec.data, lookup(r.rec.data, "lat_direction", "") == "false" ? { lat_direction = "N" } : {}) :
        contains(local.data_types, r.type) ? r.rec.data :
        null
      )
    }
  ]

  grouped = { for r in local.records : r.key => r... }

  flat_records = {
    for key, group in local.grouped : key => {
      # Cloudflare stores names in lower case; the key keeps the name as written
      name     = lower(group[0].name)
      fqdn     = group[0].fqdn
      type     = group[0].type
      content  = group[0].content
      ttl      = group[0].ttl
      proxied  = group[0].proxied
      comment  = group[0].comment
      tags     = group[0].tags
      settings = group[0].settings
      priority = group[0].priority
      data     = group[0].data
    }
  }

  state_migration = {
    for r in local.records : r.old_key => r.key if r.old_key != r.key
  }
}

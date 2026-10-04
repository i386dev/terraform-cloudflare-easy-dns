# Invariants over all records, reported by the preconditions of output.flat_records
# (outputs.tf): they compare records with each other or with other inputs, which
# validations of var.records cannot do on Terraform 1.8.

locals {
  # The same record written with different name forms ("www" and "www.example.com",
  # "@" and the zone name) gets different keys, so it is checked separately
  by_identity = { for r in local.records : "${r.fqdn} ${r.key_value}" => r... }

  duplicates = concat(
    [
      for key, group in local.grouped : "\"${key}\" from ${join(" and ", [for r in group : r.source])}"
      if length(group) > 1
    ],
    [
      for identity, group in local.by_identity : "\"${identity}\" as ${join(" and ", [for r in group : "\"${r.key}\" from ${r.source}"])}"
      if length(distinct([for r in group : r.key])) > 1
    ],
  )

  # A CNAME cannot share its name with other records, except at the zone apex (CNAME
  # flattening) and on names listed in allowed_cname_conflicts (existing zones,
  # where Cloudflare accepted it for records that are not proxied). A name never
  # has more than one CNAME, whatever keys the records have. Names are grouped
  # fully qualified.
  by_name = { for r in local.records : r.fqdn => r... }
  cname_shared = [
    for name, group in local.by_name : name
    if name != lower(local.zone) && anytrue([for r in group : r.type == "CNAME"]) && anytrue([for r in group : r.type != "CNAME"])
  ]
  allowed_cname_conflicts = distinct([for n in var.allowed_cname_conflicts : local.fqdn[n]])
  cname_conflicts = [
    for name, group in local.by_name : "\"${name}\": ${join(", ", [for r in group : "${r.type} from ${r.source}"])}"
    if length([for r in group : r if r.type == "CNAME"]) > 1
    || (contains(local.cname_shared, name) && !contains(local.allowed_cname_conflicts, name))
  ]
  # TTLs below minimum_ttl (records that are not proxied; 1 means automatic), and a
  # default_ttl below it even when no record uses it. The plan is not known here, so a
  # zone on Enterprise opts in with minimum_ttl = 30
  low_ttls = concat(
    var.default_ttl != 1 && var.default_ttl < var.minimum_ttl ? ["default_ttl (${var.default_ttl})"] : [],
    [
      for r in local.records : "\"${r.key}\" (ttl ${r.ttl}) from ${r.source}"
      if !r.proxied && r.ttl != 1 && r.ttl < var.minimum_ttl
    ],
  )

  # A wildcard is only valid as the whole leftmost label. Names, prefixes and aliases
  # are checked on their own in the records validation; this checks the names they
  # combine into ("_acme-challenge" under "*" gives "_acme-challenge.*") and the
  # targets of inline aliases ("cdn.ALIASES" under "*.app" gives "cdn.*.app")
  combined_names = concat(
    [for i, e in local.entries : { name = local.entry_names[i], source = e.source }],
    [
      for e in local.entries : { name = "${e.prefix}.${e.base_name == "@" ? local.zone : e.base_name}", source = "${e.source} (alias target)" }
      if e.kind == "ALIASES" && e.prefix != null
    ],
  )
  misplaced_wildcards = [
    for n in local.combined_names : "\"${n.name}\" from ${n.source}"
    if n.name != "*" && !can(regex("^(\\*\\.)?[^*]*$", n.name))
  ]

  # Each part of a name is checked on its own in the records validation; the name
  # they combine into with the zone must still fit into 253 characters. The same goes
  # for the targets that ALIASES build from a prefix and a name (CNAME targets written
  # in the configuration are limited by the validation already)
  long_names = distinct(concat(
    [
      for r in local.records : "\"${r.fqdn}\" (${length(r.fqdn)} characters) from ${r.source}"
      if length(r.fqdn) > 253
    ],
    [
      for r in local.records : "\"${trimsuffix(r.content, ".")}\" (${length(trimsuffix(r.content, "."))} characters), the target of \"${r.key}\" from ${r.source}"
      if r.type == "CNAME" && length(trimsuffix(r.content == null ? "" : r.content, ".")) > 253
    ],
  ))

  # A CNAME pointing to its own name is a loop. Targets are compared like names: case,
  # a trailing dot, "@" and the short form ("www" on www.example.com) do not matter
  self_cnames = [
    for r in local.records : "\"${r.key}\" from ${r.source}"
    # Terraform 1.8 evaluates both sides of &&, and records of other types may have no content
    if r.type == "CNAME" && contains([
      lower(trimsuffix((r.content == null ? "" : r.content), ".")),
      "${lower(trimsuffix((r.content == null ? "" : r.content), "."))}.${lower(local.zone)}",
      trimsuffix((r.content == null ? "" : r.content), ".") == "@" ? lower(local.zone) : "",
    ], r.fqdn)
  ]

  # Listed names that no longer have a conflict, so the list does not keep growing
  unused_allowed_cname_conflicts = [for n in local.allowed_cname_conflicts : n if !contains(local.cname_shared, n)]
}

check "allowed_cname_conflicts_in_use" {
  assert {
    condition     = length(local.unused_allowed_cname_conflicts) == 0
    error_message = "allowed_cname_conflicts lists names without a CNAME conflict, which can be removed: ${join(", ", local.unused_allowed_cname_conflicts)}"
  }
}

# Matching of records that already exist in the zone to the configured records,
# so they can be adopted with import blocks instead of being created again

locals {
  # Names, hostnames and hex values are compared case-insensitively and without a
  # trailing dot, other values exactly. OPENPGPKEY content is base64, so it is
  # compared exactly.
  #
  # Cloudflare stores TXT content as it was sent, and v=spf1 "a" -all and
  # "v=spf1 \"a\" -all" are the same DNS record. So TXT values are joined from
  # quoted chunks, and a quoted value loses its surrounding quotes and its escapes
  # (\" and \\); quotes inside the value still count.
  txt_chunks_joined = { for r in var.existing_records : r.id => r.content == null ? "" : replace(r.content, "\" \"", "") }
  existing_txt = {
    for id, v in local.txt_chunks_joined : id => (
      length(v) >= 2 && startswith(v, "\"") && endswith(v, "\"")
      ? replace(replace(substr(v, 1, length(v) - 2), "\\\"", "\""), "\\\\", "\\")
      : v
    )
  }
  existing = [
    for r in var.existing_records : {
      id   = r.id
      name = lower(trimsuffix(r.name, "."))
      type = r.type
      content = r.content == null ? null : (
        r.type == "TXT" ? local.existing_txt[r.id] : contains(local.exact_content_types, r.type) ? r.content : lower(trimsuffix(r.content, "."))
      )
      priority = r.priority
      data     = coalesce(r.data, {})
    }
  ]

  # Record types whose content is not a hostname or an address
  exact_content_types = ["OPENPGPKEY"]

  # Fields of structured records that hold hostnames or hex strings (the target of a
  # URI record is a URI, compared exactly: paths and queries are case-sensitive)
  case_insensitive_fields = ["target", "replacement", "digest", "fingerprint"]

  # CAA issue/issuewild values are "<issuer domain>[; parameters]": the domain is
  # compared like a hostname, the parameters (account URIs, ...) exactly
  caa_issuer_tags = ["issue", "issuewild"]

  configured_txt_joined = {
    for key, rec in local.flat_records : key => replace(rec.content, "\" \"", "")
    if rec.type == "TXT"
  }
  configured_txt = {
    for key, v in local.configured_txt_joined : key => (
      length(v) >= 2 && startswith(v, "\"") && endswith(v, "\"")
      ? replace(replace(substr(v, 1, length(v) - 2), "\\\"", "\""), "\\\\", "\\")
      : v
    )
  }

  import_matches = {
    for key, rec in local.flat_records : key => [
      for e in local.existing : e.id
      if e.type == rec.type
      && e.name == rec.fqdn
      && (
        rec.data == null
        ? e.content == (
          rec.type == "TXT" ? local.configured_txt[key] : contains(local.exact_content_types, rec.type) ? rec.content : lower(trimsuffix(rec.content, "."))
        )
        : alltrue([
          for field, value in rec.data : (
            (contains(local.case_insensitive_fields, field) && !(field == "target" && rec.type == "URI")) || (field == "certificate" && contains(["TLSA", "SMIMEA"], rec.type))
            ? lower(trimsuffix(lookup(e.data, field, ""), ".")) == lower(trimsuffix(value, "."))
            : rec.type == "CAA" && field == "value" && contains(local.caa_issuer_tags, lookup(rec.data, "tag", ""))
            ? format("%s%s", lower(trimsuffix(trimspace(split(";", lookup(e.data, field, ""))[0]), ".")), substr(lookup(e.data, field, ""), length(split(";", lookup(e.data, field, ""))[0]), -1))
            == format("%s%s", lower(trimsuffix(trimspace(split(";", value)[0]), ".")), substr(value, length(split(";", value)[0]), -1))
            : lookup(e.data, field, "") == value
          )
        ])
      )
    ]
  }

  # Only unambiguous matches: records with no match are new, records with several
  # matches (duplicates in the zone) are left for manual review
  single_matches = {
    for key, ids in local.import_matches : key => ids[0]
    if length(ids) == 1
  }

  # An existing record can be imported into one address only. Configured records that
  # differ only in priority (MX, URI) match the same existing record: the one with the
  # same priority gets it, and the others are new records. Without such a record, or
  # with several, none of them is imported.
  existing_priority = { for e in local.existing : e.id => e.priority }
  claims            = { for key, id in local.single_matches : id => key... }
  claim_winners = {
    for id, keys in local.claims : id => (
      length(keys) == 1 ? keys : [
        for key in keys : key
        if local.flat_records[key].priority != null && local.existing_priority[id] != null && local.flat_records[key].priority == local.existing_priority[id]
      ]
    )
  }
  import_record_ids = {
    for id, keys in local.claim_winners : keys[0] => id
    if length(keys) == 1
  }
  import_duplicates = merge(
    { for key, ids in local.import_matches : key => ids if length(ids) > 1 },
    {
      for claim in flatten([
        for id, keys in local.claims : [for key in keys : { key = key, id = id }]
        if length(local.claim_winners[id]) != 1
      ]) : claim.key => [claim.id]
    },
  )
}

check "import_duplicates" {
  assert {
    condition     = length(local.import_duplicates) == 0
    error_message = "Records that match several existing records, or that match the same existing record as other configured records, are not imported and would be created again; remove the duplicates from the zone, or give the records distinct values or priorities (see the import_duplicates output):\n${join("\n", [for key, ids in local.import_duplicates : "\"${key}\": ${join(", ", ids)}"])}"
  }
}

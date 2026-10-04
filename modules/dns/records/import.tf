# Matching of records that already exist in the zone to the configured records,
# so they can be adopted with import blocks instead of being created again

locals {
  # Names, hostnames and hex values are compared case-insensitively and without a
  # trailing dot, other values exactly. OPENPGPKEY content is base64, so it is
  # compared exactly.
  #
  # Cloudflare stores TXT content as it was sent, and v=spf1 "a" -all and
  # "v=spf1 \"a\" -all" are the same DNS record. A value in the zone file form
  # (one or more quoted chunks, "a" "b", with no escapes other than \" and \\) is
  # compared as its chunks joined and unescaped; a value without a leading quote is
  # literal text, compared as written, so prefix" "suffix is not prefixsuffix. A value
  # with a leading quote that is not in that form (such as "\065", where \065 is a
  # decimal escape, "A" in zone files) is opaque: it only matches the same text, never
  # a decoded value. The comparison value is the pair, as JSON.
  txt_zone_file_form = "^\"(?:[^\"\\\\]|\\\\[\"\\\\])*\"(?:[ \\t]+\"(?:[^\"\\\\]|\\\\[\"\\\\])*\")*$"
  txt_chunk          = "\"((?:[^\"\\\\]|\\\\[\"\\\\])*)\""
  existing_txt = {
    for r in var.existing_records : r.id => (
      r.content == null ? "" :
      can(regex(local.txt_zone_file_form, r.content))
      ? jsonencode({ opaque = false, value = replace(join("", [for chunk in regexall(local.txt_chunk, r.content) : chunk[0]]), "/\\\\([\"\\\\])/", "$1") })
      : jsonencode({ opaque = startswith(r.content, "\""), value = r.content })
    )
  }
  existing = [
    for r in var.existing_records : {
      id   = r.id
      name = lower(trimsuffix(r.name, "."))
      type = r.type
      content = r.content == null ? null : (
        r.type == "TXT" ? local.existing_txt[r.id] :
        contains(local.exact_content_types, r.type) ? r.content :
        r.type == "AAAA" && can(cidrhost("${r.content}/128", 0)) ? (strcontains(cidrhost("${r.content}/128", 0), ":") ? cidrhost("${r.content}/128", 0) : "::ffff:${cidrhost("${r.content}/128", 0)}") :
        lower(trimsuffix(r.content, "."))
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

  configured_txt = {
    for key, rec in local.flat_records : key => (
      can(regex(local.txt_zone_file_form, rec.content))
      ? jsonencode({ opaque = false, value = replace(join("", [for chunk in regexall(local.txt_chunk, rec.content) : chunk[0]]), "/\\\\([\"\\\\])/", "$1") })
      : jsonencode({ opaque = startswith(rec.content, "\""), value = rec.content })
    )
    if rec.type == "TXT"
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

  # Configured records with a priority (MX, URI) that match several existing records
  # take the one with the same priority (a zone with MX 10 and MX 20 on one host).
  # Without such a record, or with several, the matches stay ambiguous
  existing_priority = { for e in local.existing : e.id => e.priority }
  narrowed_matches = {
    for key, ids in local.import_matches : key => (
      length(ids) > 1 && local.flat_records[key].priority != null
      && length([for id in ids : id if local.existing_priority[id] == local.flat_records[key].priority]) == 1
      ? [for id in ids : id if local.existing_priority[id] == local.flat_records[key].priority]
      : ids
    )
  }

  # Only unambiguous matches: records with no match are new, records with several
  # matches (duplicates in the zone) are not imported, and the plan stops on them
  single_matches = {
    for key, ids in local.narrowed_matches : key => ids[0]
    if length(ids) == 1
  }

  # An existing record can be imported into one address only. Configured records that
  # differ only in priority (MX, URI) match the same existing record: the one with the
  # same priority gets it, and the others are new records. Without such a record, or
  # with several, none of them is imported.
  claims = { for key, id in local.single_matches : id => key... }
  claim_winners = {
    for id, keys in local.claims : id => (
      length(keys) == 1 ? keys : [
        for key in keys : key
        if local.flat_records[key].priority != null && local.existing_priority[id] != null && local.flat_records[key].priority == local.existing_priority[id]
      ]
    )
  }
  matched_record_ids = {
    for id, keys in local.claim_winners : keys[0] => id
    if length(keys) == 1
  }
  matched_duplicates = merge(
    { for key, ids in local.narrowed_matches : key => ids if length(ids) > 1 },
    {
      for claim in flatten([
        for id, keys in local.claims : [for key in keys : { key = key, id = id }]
        if length(local.claim_winners[id]) != 1
      ]) : claim.key => [claim.id]
    },
  )

  # Without import_existing, the existing records are only reported (unmanaged
  # records), so nothing is imported and an ambiguous match does not stop the plan
  import_record_ids = { for key, id in local.matched_record_ids : key => id if var.import_existing }
  import_duplicates = { for key, ids in local.matched_duplicates : key => ids if var.import_existing }

  # Existing records that no configured record matches: records in the zone that the
  # configuration does not describe. For the report, a configured record with a
  # priority describes only the existing records of that priority (MX 20 next to, or
  # instead of, the configured MX 10 is unmanaged), unless the import adopts it
  report_matches = {
    for key, ids in local.import_matches : key => (
      local.flat_records[key].priority != null
      ? [for id in ids : id if local.existing_priority[id] == local.flat_records[key].priority]
      : ids
    )
  }
  matched_ids = toset(concat(flatten(values(local.report_matches)), values(local.import_record_ids)))

  # Configured records that several existing records match (copies of one record) for
  # the report: type, name and IDs only, since record keys may contain origin
  # addresses
  report_ambiguous = {
    for key, ids in local.report_matches : key => {
      type = local.flat_records[key].type
      name = local.flat_records[key].fqdn
      ids  = ids
    } if length(ids) > 1
  }
  unmanaged_records = [
    for r in var.existing_records : {
      id       = r.id
      name     = r.name
      type     = r.type
      content  = r.content
      priority = r.priority
      data     = r.data
    }
    if !contains(local.matched_ids, r.id)
  ]
}

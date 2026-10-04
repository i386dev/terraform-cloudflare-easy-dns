# Matching of records that already exist in the zone to the configured records

variables {
  root_domain = "example.com"
  records = {
    "@" = {
      TXT     = [{ content = "v=spf1 include:_spf.example.net ~all" }]
      MX      = [{ content = "mail.example.com", priority = 10 }]
      CAA     = [{ content = "letsencrypt.org", tag = "issue" }]
      ALIASES = [{ content = "www" }]
    }
    "app" = {
      A = [{ content = "30.40.50.60" }, { content = "30.40.50.61" }]
    }
    "_sip._tcp" = {
      SRV = [{ key = "sip", data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } }]
    }
    "dup" = {
      A = [{ content = "1.1.1.1" }]
    }
  }
  existing_records = [
    { id = "id-a", name = "App.Example.com", type = "A", content = "30.40.50.60" },
    { id = "id-txt", name = "example.com", type = "TXT", content = "\"v=spf1 include:_spf.example.net\" \" ~all\"" },
    { id = "id-cname", name = "www.example.com", type = "CNAME", content = "Example.com." },
    { id = "id-mx", name = "example.com", type = "MX", content = "mail.example.com" },
    { id = "id-caa", name = "example.com", type = "CAA", data = { flags = "0", tag = "issue", value = "letsencrypt.org" } },
    { id = "id-srv", name = "_sip._tcp.example.com", type = "SRV", data = { priority = "10", weight = "5", port = "5060", target = "sip.example.com." } },
    { id = "id-dup-1", name = "dup.example.com", type = "A", content = "1.1.1.1" },
    { id = "id-dup-2", name = "dup.example.com", type = "A", content = "1.1.1.1" },
    { id = "id-other", name = "other.example.com", type = "A", content = "9.9.9.9" },
    { id = "id-wrong-type", name = "app.example.com", type = "AAAA", content = "30.40.50.61" },
  ]
}

run "import_record_ids" {
  command = plan

  variables {
    # The zone without the duplicated "dup" records
    existing_records = [
      { id = "id-a", name = "App.Example.com", type = "A", content = "30.40.50.60" },
      { id = "id-txt", name = "example.com", type = "TXT", content = "\"v=spf1 include:_spf.example.net\" \" ~all\"" },
      { id = "id-cname", name = "www.example.com", type = "CNAME", content = "Example.com." },
      { id = "id-mx", name = "example.com", type = "MX", content = "mail.example.com" },
      { id = "id-caa", name = "example.com", type = "CAA", data = { flags = "0", tag = "issue", value = "letsencrypt.org" } },
      { id = "id-srv", name = "_sip._tcp.example.com", type = "SRV", data = { priority = "10", weight = "5", port = "5060", target = "sip.example.com." } },
      { id = "id-other", name = "other.example.com", type = "A", content = "9.9.9.9" },
      { id = "id-wrong-type", name = "app.example.com", type = "AAAA", content = "30.40.50.61" },
    ]
  }

  assert {
    condition = output.import_record_ids == {
      "app A 30.40.50.60"                                                    = "id-a"
      "@ TXT ${substr(sha1("v=spf1 include:_spf.example.net ~all"), 0, 12)}" = "id-txt"
      "www CNAME"                                                            = "id-cname"
      "@ MX mail.example.com"                                                = "id-mx"
      "@ CAA issue letsencrypt.org"                                          = "id-caa"
      "_sip._tcp SRV sip"                                                    = "id-srv"
    }
    error_message = "New records and unrelated records must be left out"
  }
}

# Two identical records in the zone: the import is ambiguous, and the plan stops
run "import_duplicates_stop_the_plan" {
  command = plan

  expect_failures = [output.import_record_ids]

  assert {
    condition     = output.import_duplicates == { "dup A 1.1.1.1" = ["id-dup-1", "id-dup-2"] }
    error_message = "Records with several matches must be listed with all matching IDs"
  }
}

run "no_existing_records" {
  command = plan

  variables {
    existing_records = []
  }

  assert {
    condition     = output.import_record_ids == {} && output.import_duplicates == {}
    error_message = "No import IDs without existing records"
  }
}

run "import_txt_quotes_inside_the_value" {
  command = plan

  variables {
    records = {
      "@" = {
        TXT = [
          { content = "v=spf1 \"a\" -all" },
          { content = "plain value", key = "plain" },
        ]
      }
    }
    existing_records = [
      # Same text with the inner quotes dropped: a different value
      { id = "id-inner", name = "example.com", type = "TXT", content = "\"v=spf1 a -all\"" },
      # Only the surrounding quotes differ: the same value
      { id = "id-plain", name = "example.com", type = "TXT", content = "\"plain value\"" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ TXT plain" = "id-plain" }
    error_message = "Quotes inside a TXT value must count, surrounding quotes must not"
  }
}

run "import_structured_fields_case" {
  command = plan

  variables {
    records = {
      "_sip._udp" = {
        NAPTR = [{
          key  = "naptr"
          data = { order = 10, preference = 10, flags = "S", service = "SIP+D2U", regex = "!^.*$!sip:Info@example.com!", replacement = "_sip._udp.example.com" }
        }]
      }
    }
    existing_records = [
      # The hostname differs in case and by a trailing dot only: the same record
      { id = "id-naptr", name = "_sip._udp.example.com", type = "NAPTR", data = { order = "10", preference = "10", flags = "S", service = "SIP+D2U", regex = "!^.*$!sip:Info@example.com!", replacement = "_SIP._udp.Example.com." } },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "_sip._udp NAPTR naptr" = "id-naptr" }
    error_message = "Hostname fields must be compared case-insensitively"
  }
}

run "import_structured_fields_exact" {
  command = plan

  variables {
    records = {
      "_sip._udp" = {
        NAPTR = [{
          key  = "naptr"
          data = { order = 10, preference = 10, flags = "S", service = "SIP+D2U", regex = "!^.*$!sip:Info@example.com!", replacement = "_sip._udp.example.com" }
        }]
      }
    }
    existing_records = [
      # The regex differs in case: a different record
      { id = "id-naptr", name = "_sip._udp.example.com", type = "NAPTR", data = { order = "10", preference = "10", flags = "S", service = "SIP+D2U", regex = "!^.*$!sip:info@example.com!", replacement = "_sip._udp.example.com" } },
    ]
  }

  assert {
    condition     = output.import_record_ids == {}
    error_message = "Fields other than hostnames and hex values must match exactly"
  }
}

run "import_caa_issuer_case" {
  command = plan

  variables {
    records = {
      "@" = {
        CAA = [
          { content = "LetsEncrypt.org", tag = "issue" },
          { content = "pki.goog; accounturi=https://example.net/Acct/1", tag = "issuewild" },
          { content = "mailto:Ops@example.com", tag = "iodef" },
        ]
      }
    }
    existing_records = [
      # The issuer domain differs in case: the same record
      { id = "id-issue", name = "example.com", type = "CAA", data = { flags = "0", tag = "issue", value = "letsencrypt.org" } },
      # The account URI parameter differs in case: a different record
      { id = "id-wild", name = "example.com", type = "CAA", data = { flags = "0", tag = "issuewild", value = "PKI.goog; accounturi=https://example.net/acct/1" } },
      # iodef is a URL, compared exactly
      { id = "id-iodef", name = "example.com", type = "CAA", data = { flags = "0", tag = "iodef", value = "mailto:ops@example.com" } },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ CAA issue LetsEncrypt.org" = "id-issue" }
    error_message = "CAA issuer domains must match case-insensitively, parameters and iodef exactly"
  }
}

run "import_openpgpkey_exact" {
  command = plan

  variables {
    records = {
      "a._openpgpkey" = { OPENPGPKEY = [{ content = "mQENBAbc", key = "a" }] }
      "b._openpgpkey" = { OPENPGPKEY = [{ content = "mQENBXyz", key = "b" }] }
    }
    existing_records = [
      # base64 differing in case: a different key
      { id = "id-a", name = "a._openpgpkey.example.com", type = "OPENPGPKEY", content = "MQENBABC" },
      { id = "id-b", name = "b._openpgpkey.example.com", type = "OPENPGPKEY", content = "mQENBXyz" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "b._openpgpkey OPENPGPKEY b" = "id-b" }
    error_message = "OPENPGPKEY content must be compared exactly"
  }
}

run "import_txt_quoted_and_escaped" {
  command = plan

  variables {
    records = {
      "a" = { TXT = [{ content = "v=spf1 \"a\" -all" }] }
      "b" = { TXT = [{ content = "\"v=spf1 \\\"b\\\" -all\"" }] }
      "c" = { TXT = [{ content = "back\\slash", key = "c" }] }
    }
    existing_records = [
      # Stored in the zone file form with escaped quotes: the same DNS record as the unquoted form
      { id = "id-a", name = "a.example.com", type = "TXT", content = "\"v=spf1 \\\"a\\\" -all\"" },
      # Stored unquoted, configured in the zone file form
      { id = "id-b", name = "b.example.com", type = "TXT", content = "v=spf1 \"b\" -all" },
      # A quoted value with an escaped backslash
      { id = "id-c", name = "c.example.com", type = "TXT", content = "\"back\\\\slash\"" },
    ]
  }

  assert {
    condition     = length(output.import_record_ids) == 3 && output.import_record_ids["c TXT c"] == "id-c"
    error_message = "Quoted TXT values must be compared without their escapes"
  }
}

run "import_fully_qualified_base_name" {
  command = plan

  variables {
    records = {
      "app.example.com" = { A = [{ content = "192.0.2.1" }] }
      "App"             = { AAAA = [{ content = "2001:db8::1" }] }
    }
    existing_records = [
      { id = "id-a", name = "app.example.com", type = "A", content = "192.0.2.1" },
      { id = "id-aaaa", name = "app.example.com", type = "AAAA", content = "2001:db8::1" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "app.example.com A 192.0.2.1" = "id-a", "App AAAA 2001:db8::1" = "id-aaaa" }
    error_message = "Records with fully qualified and short base names must both be matched"
  }
}

run "import_uri_target_exact" {
  command = plan

  variables {
    records = {
      "_ftp._tcp" = {
        URI = [{ key = "upper", priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/Public" } }, { key = "lower", priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/public" } }]
      }
    }
    existing_records = [
      # URI paths are case-sensitive: each configured record matches only its own target
      { id = "id-upper", name = "_ftp._tcp.example.com", type = "URI", priority = 10, data = { weight = "1", target = "ftp://ftp.example.com/Public" } },
      { id = "id-lower", name = "_ftp._tcp.example.com", type = "URI", priority = 10, data = { weight = "1", target = "ftp://ftp.example.com/public" } },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "_ftp._tcp URI upper" = "id-upper", "_ftp._tcp URI lower" = "id-lower" }
    error_message = "The target of URI records must be compared exactly"
  }
}

# MX records that differ only in priority match the same existing record; it can be
# imported into one address only
run "import_one_id_by_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ key = "primary", content = "mail.example.com", priority = 10 }, { key = "backup", content = "mail.example.com", priority = 20 }] } }
    existing_records = [
      { id = "id-mx", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ MX primary" = "id-mx" } && length(output.import_duplicates) == 0
    error_message = "The record with the same priority gets the existing record, the other one is new"
  }
}

run "import_one_id_without_matching_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ key = "primary", content = "mail.example.com", priority = 10 }, { key = "backup", content = "mail.example.com", priority = 20 }] } }
    existing_records = [
      { id = "id-mx", name = "example.com", type = "MX", content = "mail.example.com", priority = 30 },
    ]
  }

  expect_failures = [output.import_record_ids]

  assert {
    condition     = output.import_duplicates == { "@ MX primary" = ["id-mx"], "@ MX backup" = ["id-mx"] }
    error_message = "Without a record of the same priority, none of them is imported and both are listed"
  }
}

run "import_one_id_with_unknown_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ key = "primary", content = "mail.example.com", priority = 10 }, { key = "backup", content = "mail.example.com", priority = 20 }] } }
    existing_records = [
      { id = "id-mx", name = "example.com", type = "MX", content = "mail.example.com" },
    ]
  }

  expect_failures = [output.import_record_ids]

  assert {
    condition     = length(output.import_duplicates) == 2
    error_message = "Without the priority of the existing record, none of them is imported"
  }
}

# A zone with MX 10 and MX 20 on one host: each configured record matches both and
# takes the one with its priority
run "import_several_matches_by_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ key = "primary", content = "mail.example.com", priority = 10 }, { key = "backup", content = "mail.example.com", priority = 20 }] } }
    existing_records = [
      { id = "id-mx-10", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
      { id = "id-mx-20", name = "example.com", type = "MX", content = "mail.example.com", priority = 20 },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ MX primary" = "id-mx-10", "@ MX backup" = "id-mx-20" } && length(output.import_duplicates) == 0
    error_message = "Each record takes the existing record with its priority"
  }
}

run "import_several_matches_one_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ content = "mail.example.com", priority = 10 }] } }
    existing_records = [
      { id = "id-mx-10", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
      { id = "id-mx-20", name = "example.com", type = "MX", content = "mail.example.com", priority = 20 },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "@ MX mail.example.com" = "id-mx-10" }
    error_message = "The record takes the existing record with its priority; the other one stays unmanaged"
  }
}

# Two existing records with the same priority as well: still ambiguous
run "import_several_matches_same_priority" {
  command = plan

  variables {
    records = { "@" = { MX = [{ content = "mail.example.com", priority = 10 }] } }
    existing_records = [
      { id = "id-mx-a", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
      { id = "id-mx-b", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
    ]
  }

  expect_failures = [output.import_record_ids]

  assert {
    condition     = output.import_duplicates == { "@ MX mail.example.com" = ["id-mx-a", "id-mx-b"] }
    error_message = "Several existing records with the same priority stay ambiguous"
  }
}

# Several matches and no record with the configured priority: ambiguous
run "import_several_matches_other_priorities" {
  command = plan

  variables {
    records = { "@" = { MX = [{ content = "mail.example.com", priority = 30 }] } }
    existing_records = [
      { id = "id-mx-10", name = "example.com", type = "MX", content = "mail.example.com", priority = 10 },
      { id = "id-mx-20", name = "example.com", type = "MX", content = "mail.example.com", priority = 20 },
    ]
  }

  expect_failures = [output.import_record_ids]

  assert {
    condition     = jsonencode(output.import_duplicates) == jsonencode({ "@ MX mail.example.com" = ["id-mx-10", "id-mx-20"] })
    error_message = "Without a record of the configured priority the matches stay ambiguous"
  }
}

run "import_ipv6_in_another_form" {
  command = plan

  variables {
    records          = { "app" = { AAAA = [{ content = "2001:0db8:0:0:0:0:0:1" }] } }
    existing_records = [{ id = "id-aaaa", name = "app.example.com", type = "AAAA", content = "2001:db8::1" }]
  }

  assert {
    condition     = output.import_record_ids == { "app AAAA 2001:0db8:0:0:0:0:0:1" = "id-aaaa" }
    error_message = "IPv6 addresses must be compared in their canonical form"
  }
}

# Quotes inside a value that is not in the zone file form count: prefix" "suffix is
# not prefixsuffix
run "import_txt_quote_space_quote_inside_the_value" {
  command = plan

  variables {
    records = { "app" = { TXT = [{ content = "prefix\" \"suffix", key = "q" }] } }
    existing_records = [
      { id = "id-joined", name = "app.example.com", type = "TXT", content = "prefixsuffix" },
    ]
  }

  assert {
    condition     = output.import_record_ids == {}
    error_message = "A value with quotes inside must not match the value without them"
  }
}

run "import_txt_quote_space_quote_same_value" {
  command = plan

  variables {
    records = { "app" = { TXT = [{ content = "prefix\" \"suffix", key = "q" }] } }
    existing_records = [
      { id = "id-same", name = "app.example.com", type = "TXT", content = "prefix\" \"suffix" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "app TXT q" = "id-same" }
    error_message = "The same value must match"
  }
}

# Chunks in the zone file form with escaped quotes and backslashes
run "import_txt_chunks_with_escapes" {
  command = plan

  variables {
    records = {
      "app" = {
        TXT = [
          { content = "v=spf1 \"a\" -all", key = "spf" },
          { content = "a\\b", key = "backslash" },
        ]
      }
    }
    existing_records = [
      { id = "id-spf", name = "app.example.com", type = "TXT", content = "\"v=spf1 \\\"a\\\"\" \" -all\"" },
      { id = "id-backslash", name = "app.example.com", type = "TXT", content = "\"a\\\\b\"" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "app TXT spf" = "id-spf", "app TXT backslash" = "id-backslash" }
    error_message = "Chunks must be joined and unescaped"
  }
}

# Only \" and \\ are unescaped. A value with another escape, such as the decimal
# escape \065 ("A" in zone files), is compared exactly: "\065" is not "\\065"
run "import_txt_decimal_escape_compared_exactly" {
  command = plan

  variables {
    records = {
      "app" = {
        TXT = [
          { content = "\\065", key = "backslash" },
          { content = "\"\\065\"", key = "decimal" },
        ]
      }
    }
    existing_records = [
      { id = "id-decimal", name = "app.example.com", type = "TXT", content = "\"\\065\"" },
      { id = "id-backslash", name = "app.example.com", type = "TXT", content = "\"\\\\065\"" },
    ]
  }

  assert {
    condition     = output.import_record_ids == { "app TXT backslash" = "id-backslash", "app TXT decimal" = "id-decimal" }
    error_message = "A decimal escape must not match an escaped backslash with digits"
  }
}

run "import_ipv4_mapped_in_another_form" {
  command = plan

  variables {
    records          = { "app" = { AAAA = [{ content = "::ffff:c000:201" }] } }
    existing_records = [{ id = "id-mapped", name = "app.example.com", type = "AAAA", content = "::ffff:192.0.2.1" }]
  }

  assert {
    condition     = output.import_record_ids == { "app AAAA ::ffff:c000:201" = "id-mapped" }
    error_message = "IPv4-mapped addresses must be compared in one form"
  }
}

# A value that is not in the supported zone file form is opaque: it never matches the
# decoded value of another one, in both directions (contents below as sent:
# "\065" and "\"\\065\"", "v=spf1 \045all" quoted and its escaped form)
run "import_txt_opaque_never_matches_a_decoded_value" {
  command = plan

  variables {
    records = {
      "app" = {
        TXT = [
          { content = "\"\\065\"", key = "opaque" },
          { content = "\"\\\"v=spf1 \\\\045all\\\"\"", key = "encoded" },
        ]
      }
    }
    existing_records = [
      { id = "id-encoded", name = "app.example.com", type = "TXT", content = "\"\\\"\\\\065\\\"\"" },
      { id = "id-opaque", name = "app.example.com", type = "TXT", content = "\"v=spf1 \\045all\"" },
    ]
  }

  assert {
    condition     = output.import_record_ids == {}
    error_message = "An opaque value must not match a decoded one"
  }
}

run "import_txt_opaque_same_text" {
  command = plan

  variables {
    records          = { "app" = { TXT = [{ content = "\"v=spf1 \\045all\"", key = "spf" }] } }
    existing_records = [{ id = "id-spf", name = "app.example.com", type = "TXT", content = "\"v=spf1 \\045all\"" }]
  }

  assert {
    condition     = output.import_record_ids == { "app TXT spf" = "id-spf" }
    error_message = "An opaque value matches the same text"
  }
}


# Record parsing, aliases and validation are covered by the tests of modules/dns/records.
# These tests cover only how records are mapped to the provider resource.

mock_provider "cloudflare" {
  override_data {
    target = data.cloudflare_zone.this[0]
    values = { name = "looked-up.com" }
  }
}

variables {
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "app" = {
      A       = [{ content = "30.40.50.60", proxied = true }]
      TXT     = [{ content = "v=spf1 ~all", key = "spf" }]
      MX      = [{ content = "mx.example.com", priority = 5 }]
      CAA     = [{ content = "letsencrypt.org", tag = "issue" }]
      ALIASES = [{ content = "support" }]
      DNSKEY  = [{ data = { flags = 257, protocol = 3, algorithm = 13, public_key = "abc" } }]
      NAPTR   = [{ data = { order = 100, preference = 10, flags = "U", service = "E2U+sip", regex = "!^.*0sip:info@example.com!", replacement = "." } }]
    }
    "_sip._tcp" = {
      SRV = [{ key = "sip", data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" } }]
    }
  }
}

run "plan" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.record["app A 30.40.50.60"].ttl == 1 && cloudflare_dns_record.record["app A 30.40.50.60"].proxied == true
    error_message = "Proxied records must have automatic TTL"
  }

  assert {
    condition     = cloudflare_dns_record.record["app TXT spf"].ttl == 3600 && cloudflare_dns_record.record["app TXT spf"].priority == null
    error_message = "Default TTL, no priority for TXT"
  }

  assert {
    condition     = cloudflare_dns_record.record["app MX mx.example.com"].priority == 5
    error_message = "MX priority"
  }

  assert {
    condition     = cloudflare_dns_record.record["app CAA issue letsencrypt.org"].data.tag == "issue" && cloudflare_dns_record.record["app CAA issue letsencrypt.org"].data.flags == 0
    error_message = "CAA data"
  }

  assert {
    condition     = cloudflare_dns_record.record["_sip._tcp SRV sip"].priority == 10 && cloudflare_dns_record.record["_sip._tcp SRV sip"].data.port == 5060 && cloudflare_dns_record.record["_sip._tcp SRV sip"].data.target == "sip.example.com"
    error_message = "SRV data and priority"
  }

  assert {
    condition     = cloudflare_dns_record.record["app DNSKEY ${substr(sha1(jsonencode({ flags = "257", protocol = "3", algorithm = "13", public_key = "abc" })), 0, 12)}"].data.flags == 257
    error_message = "DNSKEY flags"
  }

  assert {
    condition     = one([for k, r in cloudflare_dns_record.record : r.data.flags if r.type == "NAPTR"]) == "U"
    error_message = "NAPTR flags"
  }
}

run "zone_lookup" {
  command = plan

  variables {
    zone_name = null
  }

  assert {
    condition     = cloudflare_dns_record.record["support CNAME"].content == "app.looked-up.com"
    error_message = "Zone lookup"
  }
}

run "comments_and_tags" {
  command = plan

  variables {
    default_comment = "Managed by Terraform"
    default_tags    = ["managed-by:terraform"]
    records = {
      "app" = {
        A    = [{ content = "192.0.2.1", comment = "Web", tags = ["role:web"] }]
        AAAA = [{ content = "2001:db8::1" }]
      }
    }
  }

  assert {
    condition     = cloudflare_dns_record.record["app A 192.0.2.1"].comment == "Web" && cloudflare_dns_record.record["app AAAA 2001:db8::1"].comment == "Managed by Terraform"
    error_message = "Comments are passed to the resource"
  }

  assert {
    condition     = toset(cloudflare_dns_record.record["app A 192.0.2.1"].tags) == toset(["managed-by:terraform", "role:web"])
    error_message = "Tags are passed to the resource"
  }
}

run "settings" {
  command = plan

  variables {
    records = { "app" = { AAAA = [{ content = "2001:db8::1", settings = { ipv6_only = true } }] } }
  }

  assert {
    condition     = cloudflare_dns_record.record["app AAAA 2001:db8::1"].settings.ipv6_only == true
    error_message = "Settings are passed to the resource"
  }
}

run "unknown_attribute" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "192.0.2.1", proxid = true }] } }
  }

  expect_failures = [var.records]
}

run "unknown_settings_attribute" {
  command = plan

  variables {
    records = { "app" = { AAAA = [{ content = "2001:db8::1", settings = { ipv6_onyl = true } }] } }
  }

  expect_failures = [var.records]
}

run "record_is_not_an_object" {
  command = plan

  variables {
    records = { "app" = { A = ["192.0.2.1"] } }
  }

  expect_failures = [var.records]
}

run "names_in_lower_case_and_allowed_cname_conflicts" {
  command = plan

  variables {
    records = {
      "Community" = {
        CNAME = [{ content = "forum.example.net" }]
        MX    = [{ content = "mx.example.net", priority = 10 }]
      }
    }
    allowed_cname_conflicts = ["community.example.com"]
  }

  assert {
    condition     = cloudflare_dns_record.record["Community CNAME"].name == "community" && cloudflare_dns_record.record["Community MX mx.example.net"].name == "community"
    error_message = "The resource gets the name in lower case, and the listed CNAME conflict is accepted"
  }
}

run "minimum_ttl_passed_to_the_core" {
  command = plan

  variables {
    minimum_ttl = 30
    records     = { "fast" = { A = [{ content = "192.0.2.9", ttl = 30 }] } }
  }

  assert {
    condition     = cloudflare_dns_record.record["fast A 192.0.2.9"].ttl == 30
    error_message = "minimum_ttl must reach the core module"
  }
}

run "yaml_booleans_in_text_values" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        TXT:
          - content: off
          - content: "quoted"
            comment: yes
    YAML
    )
  }

  expect_failures = [var.records]
}

run "yaml_quoted_text_values" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        TXT:
          - content: "off"
          - content: "0123"
            key: "n"
    YAML
    )
  }

  assert {
    condition     = length([for r in cloudflare_dns_record.record : r if r.content == "off" || r.content == "0123"]) == 2
    error_message = "Quoted values must stay as written"
  }
}

run "yaml_numbers_in_text_values" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      "@":
        TXT:
          - content: 0123
            key: "n"
    YAML
    )
  }

  expect_failures = [check.records_text_values_are_strings]
}

# Import through the wrapper: one lookup per record type of the configuration, ALIASES
# looked up as CNAME. Matching is tested in modules/dns/records (tests/import.tftest.hcl)
# and against a real zone in tests/e2e: the mocked provider cannot return a list for the
# nested result attribute of cloudflare_dns_records
run "import_lookups_per_type" {
  command = plan

  variables {
    import_existing = true
  }

  assert {
    condition     = toset(keys(data.cloudflare_dns_records.existing)) == toset(["A", "CAA", "CNAME", "DNSKEY", "MX", "NAPTR", "SRV", "TXT"])
    error_message = "One lookup per record type, ALIASES as CNAME"
  }

  assert {
    condition     = output.import_ids == {} && output.import_duplicates == {}
    error_message = "No matches in an empty zone"
  }
}

run "no_lookups_without_import_existing" {
  command = plan

  assert {
    condition     = length(data.cloudflare_dns_records.existing) == 0
    error_message = "The zone is only read with import_existing"
  }
}

run "empty_zone_name" {
  command = plan

  variables {
    zone_name = ""
  }

  expect_failures = [var.zone_name]
}

run "unicode_zone_name" {
  command = plan

  variables {
    zone_name = "münchen.de"
  }

  expect_failures = [var.zone_name]
}

run "zone_name_with_a_trailing_dot" {
  command = plan

  variables {
    zone_name = "Example.com."
    records   = { "app" = { A = [{ content = "192.0.2.1" }], ALIASES = [{ content = "www" }] }, "api.example.com" = { A = [{ content = "192.0.2.2" }] } }
  }

  assert {
    condition     = sort([for r in values(module.records.flat_records) : r.fqdn]) == tolist(["api.example.com", "app.example.com", "www.example.com"])
    error_message = "A trailing dot and the case of zone_name do not change the names"
  }
}

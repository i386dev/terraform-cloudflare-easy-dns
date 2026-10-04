# The root module passes everything to the v5 wrapper; the wrapper and the core
# have their own tests.

mock_provider "cloudflare" {}

variables {
  zone_id   = "z"
  zone_name = "example.com"
  records = {
    "@"   = { A = [{ content = "192.0.2.1" }], ALIASES = [{ content = "www" }] }
    "app" = { TXT = [{ content = "v=spf1 -all", key = "spf" }] }
  }
}

run "plan" {
  command = plan

  assert {
    condition     = length(output.record_names) == 3
    error_message = "All records must be planned through the v5 wrapper"
  }

  assert {
    condition     = module.v5.state_migration["ALIASES_@_www"] == "www CNAME"
    error_message = "Outputs of the v5 wrapper must be passed through"
  }

  assert {
    condition     = output.import_ids == {} && output.import_duplicates == {}
    error_message = "No import lookup unless import_existing is true"
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

run "unicode_zone_name" {
  command = plan

  variables {
    zone_name = "münchen.de"
  }

  expect_failures = [var.zone_name]
}

run "yaml_booleans_in_tags" {
  command = plan

  variables {
    records = yamldecode(<<-YAML
      app:
        A:
          - content: 192.0.2.1
            tags: [N]
    YAML
    )
  }

  expect_failures = [var.records]
}

# A module call may pass optional inputs through as null; null means the default
run "null_defaults" {
  command = plan

  variables {
    default_ttl     = null
    default_proxied = null
    default_tags    = null
  }

  assert {
    condition     = length(output.record_names) == 3
    error_message = "null defaults are passed to the v5 wrapper as the defaults"
  }
}

run "booleans_in_a_set_of_tags" {
  command = plan

  variables {
    records = { "app" = { A = [{ content = "192.0.2.1", tags = toset([false]) }] } }
  }

  expect_failures = [var.records]
}

run "fractional_default_ttl" {
  command = plan

  variables {
    default_ttl = 3600.5
  }

  expect_failures = [var.default_ttl]
}

# The same document as the schema tests, through yamldecode like a dns.yaml
run "yaml_all_types" {
  command = plan

  variables {
    records = yamldecode(file("tests/fixtures/all-types.yaml")).records
  }

  assert {
    condition     = length(output.record_names) == 25
    error_message = "All records of the fixture must be planned"
  }

  assert {
    condition     = one([for k, r in module.v5.records : k if startswith(k, "office LOC")]) != null
    error_message = "The LOC record with an unquoted N must be accepted"
  }
}

# Module-level defaults, comments and tags

variables {
  root_domain     = "example.com"
  default_ttl     = 300
  default_proxied = true
  default_comment = "Managed by Terraform"
  default_tags    = ["managed-by:terraform"]
  records = {
    "app" = {
      A    = [{ content = "192.0.2.1" }, { content = "192.0.2.2", ttl = 60, proxied = false, comment = "Backup", tags = ["role:backup", "managed-by:terraform"] }]
      TXT  = [{ content = "v=spf1 -all" }]
      AAAA = [{ content = "2001:db8::1", settings = { ipv6_only = true } }]
    }
    "@" = { ALIASES = [{ content = "www" }] }
  }
}

run "defaults" {
  command = plan

  assert {
    condition     = output.flat_records["app A 192.0.2.1"].ttl == 300 && output.flat_records["app A 192.0.2.1"].proxied == true
    error_message = "default_ttl and default_proxied apply to records without their own values"
  }

  assert {
    condition     = output.flat_records["app A 192.0.2.2"].ttl == 60 && output.flat_records["app A 192.0.2.2"].proxied == false
    error_message = "Record values override the defaults"
  }

  assert {
    condition     = output.flat_records["app TXT ${substr(sha1("v=spf1 -all"), 0, 12)}"].proxied == false
    error_message = "default_proxied applies only to A, AAAA, CNAME and ALIASES"
  }

  assert {
    condition     = output.flat_records["www CNAME"].proxied == true
    error_message = "default_proxied applies to aliases"
  }

  assert {
    condition     = output.flat_records["app A 192.0.2.1"].comment == "Managed by Terraform" && output.flat_records["app A 192.0.2.2"].comment == "Backup"
    error_message = "Record comments override default_comment"
  }

  assert {
    condition     = output.flat_records["app A 192.0.2.1"].tags == tolist(["managed-by:terraform"]) && output.flat_records["app A 192.0.2.2"].tags == tolist(["managed-by:terraform", "role:backup"])
    error_message = "Record tags are added to default_tags without duplicates"
  }

  assert {
    condition     = output.flat_records["app AAAA 2001:db8::1"].settings.ipv6_only == true
    error_message = "Settings are passed through"
  }
}

run "invalid_default_ttl" {
  command = plan

  variables {
    default_ttl = 5
  }

  expect_failures = [var.default_ttl]
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
    condition     = output.flat_records["app A 192.0.2.1"].ttl == 3600 && output.flat_records["app A 192.0.2.1"].proxied == false
    error_message = "null default_ttl and default_proxied mean 3600 and false"
  }

  assert {
    condition     = length(output.flat_records["app TXT ${substr(sha1("v=spf1 -all"), 0, 12)}"].tags) == 0
    error_message = "null default_tags means no tags"
  }
}

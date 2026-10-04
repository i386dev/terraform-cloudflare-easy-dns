output "records" {
  description = "Records of all types supported by the provider v5"
  value = {
    (local.p) = {
      A = [{ content = var.a_value }, { content = "192.0.2.11", ttl = 600 }]
      # Not in the canonical form (2001:db8::10, ::ffff:192.0.2.10), which Cloudflare
      # stores: no drift and a match on import show that the module sends and compares
      # the canonical form
      AAAA          = [{ content = "2001:0DB8:0:0:0:0:0:10" }, { content = "::FFFF:C000:20A" }]
      TXT           = [{ content = "v=spf1 -all" }, { key = "rotating", content = var.txt_value }]
      MX            = [{ content = "mx.${local.z}", priority = 10 }]
      CAA           = [{ content = "letsencrypt.org", tag = "issue" }]
      "_dmarc.TXT"  = [{ content = "v=DMARC1; p=none" }]
      ALIASES       = [{ content = "alias-${local.p}" }]
      "www.ALIASES" = [{ content = "inline-${local.p}" }]
    }
    "proxied-${local.p}" = { CNAME = [{ content = "example.com", proxied = true }] }
    "_sip._tcp.${local.p}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${local.z}" } }]
    }
    "_ftp._tcp.${local.p}" = {
      URI = [{ priority = 10, data = { weight = 1, target = "ftp://ftp.example.com/" } }]
    }
    "svc.${local.p}" = {
      HTTPS = [{ data = { priority = 1, target = ".", value = "alpn=\"h2\"" } }]
      SVCB  = [{ data = { priority = 1, target = "svc.example.com", value = "port=\"8443\"" } }]
    }
    "_25._tcp.${local.p}" = {
      TLSA = [{ data = { usage = 3, selector = 1, matching_type = 1, certificate = "0000000000000000000000000000000000000000000000000000000000000001" } }]
    }
    "ssh.${local.p}" = {
      SSHFP = [{ data = { algorithm = 4, type = 2, fingerprint = "0000000000000000000000000000000000000000000000000000000000000002" } }]
    }
    "naptr.${local.p}" = {
      NAPTR = [{ data = { order = 100, preference = 10, flags = "U", service = "E2U+sip", regex = "!^.*$!sip:info@example.com!", replacement = "." } }]
    }
    "loc.${local.p}" = {
      LOC = [{ data = { lat_degrees = 59, lat_minutes = 26, lat_seconds = 14, lat_direction = "N", long_degrees = 24, long_minutes = 44, long_seconds = 43, long_direction = "E", altitude = 30, size = 1, precision_horz = 10, precision_vert = 10 } }]
    }
  }
}

output "migration_records" {
  description = "Records used to check the migration from provider v4 to v5"
  value = {
    "m-${local.p}" = {
      A       = [{ content = "192.0.2.30" }]
      TXT     = [{ content = "v=spf1 -all" }]
      MX      = [{ content = "mx.${local.z}", priority = 10 }]
      CAA     = [{ content = "letsencrypt.org", tag = "issue" }]
      ALIASES = [{ content = "m-alias-${local.p}" }]
    }
    "_sip._tcp.m-${local.p}" = {
      SRV = [{ data = { priority = 10, weight = 5, port = 5060, target = "sip.${local.z}" } }]
    }
  }
}

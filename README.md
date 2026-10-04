# Cloudflare DNS Records Factory (Terraform Module)

[![Release](https://img.shields.io/github/v/release/i386dev/terraform-cloudflare-easy-dns)](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases/latest) [![CI](https://github.com/i386dev/terraform-cloudflare-easy-dns/actions/workflows/ci.yml/badge.svg)](https://github.com/i386dev/terraform-cloudflare-easy-dns/actions/workflows/ci.yml) [![End-to-end](https://github.com/i386dev/terraform-cloudflare-easy-dns/actions/workflows/e2e.yml/badge.svg)](https://github.com/i386dev/terraform-cloudflare-easy-dns/actions/workflows/e2e.yml) [![License: MIT](https://img.shields.io/badge/license-MIT-blue)](https://github.com/i386dev/terraform-cloudflare-easy-dns/blob/main/LICENSE)

A flexible Terraform module to manage Cloudflare DNS records using a structured object-based approach. Instead of defining multiple record resources, you can define your entire DNS zone (or sub-sections of it) in a single hierarchical map.


## How It Works in 30 Seconds

The zone is described as one map, grouped by name and then by record type:

```
records[<name>][<TYPE>] = [ <record>, ... ]
```

| Key | Meaning |
|:----|:--------|
| `<name>` | A name within the zone: `app`, `app.example.com`, `@` (apex), `*.app` (wildcard) |
| `<TYPE>` | A record on `<name>`: `A`, `TXT`, `MX`, ... |
| `<prefix>.<TYPE>` | A record on `<prefix>.<name>`: `"_acme-challenge.TXT"` |
| `ALIASES` | CNAMEs named by each `content`, pointing to `<name>` |
| `<prefix>.ALIASES` | CNAMEs named by each `content`, pointing to `<prefix>.<name>` |

Each record becomes one Cloudflare DNS record, with a stable address in the Terraform state:

```hcl
module "dns" {
  source = "./modules/easy-dns"

  zone_id   = var.zone_id
  zone_name = "example.com"

  records = {
    "app" = {
      # app.example.com
      A = [{ content = "192.0.2.10" }]

      # _acme-challenge.app.example.com
      "_acme-challenge.TXT" = [{ key = "acme", content = "token" }]

      # www.example.com -> CNAME -> app.example.com
      ALIASES = [{ content = "www" }]
    }
  }
}
```

Each record is an instance of `module.dns.module.v5.cloudflare_dns_record.record`, with these keys:

| Record | Key in the state |
|:-------|:-----------------|
| `app.example.com A 192.0.2.10` | `app A 192.0.2.10` |
| `_acme-challenge.app.example.com TXT "token"` | `_acme-challenge.app TXT acme` |
| `www.example.com CNAME app.example.com` | `www CNAME` |

- **Names**: `"app"` is the name within the zone (`"@"` for the apex). A prefix before the type (`"_acme-challenge.TXT"`) is added to the name.
- **Addresses**: a record is addressed by its content, so adding or removing records in a list leaves the others alone. With `key`, the value can change without replacing the record, e.g. for tokens or DKIM keys.
- **Aliases**: `ALIASES` create CNAMEs that point to the name of the block.

Everything else (all record types, defaults, import of existing records, validation) builds on this; see the [full example](#full-example) and the sections below.

## Contents

- [Features](#features), [When Not to Use It](#when-not-to-use-it), [Structure](#structure), [Requirements](#requirements)
- [Usage](#usage): [local copy](#local-copy), [Git source](#git-source), [HCL or YAML](#hcl-or-yaml) and the [full example](#full-example)
- [Record Model](#record-model): [record types](#record-types), [aliases](#the-aliases-logic), [record keys](#record-keys)
- [Validation](#validation), [Inputs](#inputs), [Outputs](#outputs)
- [Records in YAML](#records-in-yaml) with editor support, [Recipes](#recipes)
- [Importing Existing Records](#importing-existing-records)
- [Upgrading and Migration](#upgrading-and-migration)
- [Testing](#testing)

## Features

- 📂 **Structured Schema**: Group records by their base name (subdomain or `@` for the zone apex).
- 🔗 **Smart Aliases**: Automatically create `CNAME` records pointing to your main records using the `ALIASES` key.
- 🛠 **Hybrid Names**: Support for nested subdomains like `_acme-challenge.app`.
- ☁️ **Cloudflare Optimized**: Automatic `TTL = 1` for proxied records.
- 🛡 **CAA Support**: Proper handling of CAA tags, flags, and values.
- 📥 **Import of Existing Records**: Adopt records that already exist in the zone with a single `import` block (provider v5).
- 🧩 **Structured Records**: `SRV`, `URI`, `HTTPS`, `SVCB`, `TLSA`, `SSHFP`, `DS`, `LOC` and other structured records through a single `data` map; see [Record Types](#record-types) for the supported list.
- 🔀 **Provider v4 and v5**: The same input schema for both major versions of the Cloudflare provider.
- ✅ **Input Validation**: Mistakes in record types, names, IP addresses, TTL, MX or CAA fields fail at `plan`, before reaching the Cloudflare API.
- 🏷 **Defaults, Comments and Tags**: Set the TTL, proxying, comment and tags once for all records, and override them per record.
- ✍️ **Editor Support for YAML**: A JSON Schema for records kept in YAML, for completion and highlighting of mistakes before `plan`.
- 🧪 **Tested End to End**: Every record type, updates, import and the v4 to v5 migration are tested against a real Cloudflare zone.

## When Not to Use It

The module fits zones whose records are written down and change through review. Something else fits better when:

- **Records come from other systems at run time** (service discovery, Kubernetes ingresses, an inventory): a controller such as external-dns, or `cloudflare_dns_record` with `for_each` over that data. The module needs the records at `plan`, and every value computed by another resource needs a `key` (see [Record Keys](#record-keys)).
- **The zone must match the configuration exactly**, with records that are not in it deleted: the module manages only its own records and leaves the rest of the zone alone; [import](#importing-existing-records) only adopts records that are in the configuration.
- **Records need lifecycle rules** (`prevent_destroy`, `ignore_changes`): Terraform does not let a configuration set them on the resources inside a module.
- **Records need a type or field the module does not support**: see [the recipe](#a-record-type-or-field-the-module-does-not-support) for managing them next to the module call; when that is most of the zone, plain resources are simpler.

## Structure

```
*.tf           # Root module: the v5 wrapper
modules/dns/
├── records/   # Provider-agnostic core: validation and flattening (internal)
├── v4/        # Wrapper for Cloudflare provider v4 (cloudflare_record)
└── v5/        # Wrapper for Cloudflare provider v5 (cloudflare_dns_record);
               # migrate-from-v4.tf moves the state of the v4 wrapper
examples/
├── v5/        # Records in HCL
├── yaml/      # Records in a YAML file, validated by the JSON Schema
├── import/    # Adopting a zone that already has records
└── v4/        # Provider v4, for existing configurations
schema/        # JSON Schema for records in YAML
```

Both wrappers share the same inputs, outputs and record keys, so switching between them only requires changing the `source`. The root module passes everything to the v5 wrapper, so it has the same inputs and outputs.

## Requirements

| Module | Terraform | Cloudflare provider |
|--------|-----------|---------------------|
| Root module | `>= 1.8.0` | `~> 5.26` |
| `modules/dns/v4` | `>= 1.8.0` | `~> 4.41` |
| `modules/dns/v5` | `>= 1.8.0` | `~> 5.26` |

If `zone_name` is not set, the module looks up the zone by `zone_id`, so the API token needs the `Zone:Read` permission.

> **`zone_name` must be the name of the zone that `zone_id` refers to** (a trailing dot, as in zone files, is ignored). Setting it skips the lookup (no `Zone:Read` needed), and the module cannot check it: a wrong `zone_name` makes alias targets and fully qualified names point into another domain. Leave it unset when the token can read zones.

The v4 wrapper is kept for existing configurations. Provider v4 no longer gets new features, so new configurations should use v5 (the root module), and the v4 wrapper may be removed in a future major version. See [Migrating from v4 to v5](#from-provider-v4-to-v5).

## Usage

The module is not published on the Terraform Registry. Keep a copy of it in your configuration, or use it from Git.

### Local Copy

A copy in your repository needs neither GitHub nor the Terraform Registry to get the module, and every change of the module shows up in your own history. Each [release](https://github.com/i386dev/terraform-cloudflare-easy-dns/releases) has an archive of the module with a checksum:

```sh
REPO=https://github.com/i386dev/terraform-cloudflare-easy-dns
VERSION=v2.10.2
ARCHIVE="terraform-cloudflare-easy-dns-${VERSION}.tar.gz"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/${ARCHIVE}"
curl -fsSL -O "${REPO}/releases/download/${VERSION}/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS   # macOS: shasum -a 256 --check
# Optional, from 2.9.0: the archive was built by the release workflow of this repository
gh attestation verify "${ARCHIVE}" --repo i386dev/terraform-cloudflare-easy-dns \
  --signer-workflow i386dev/terraform-cloudflare-easy-dns/.github/workflows/release.yml
mkdir -p modules/easy-dns
tar -xzf "${ARCHIVE}" -C modules/easy-dns
```

Commit `modules/easy-dns` together with your configuration and use it as a local module:

| Cloudflare provider | `source` |
|:--------------------|:---------|
| v5 | `./modules/easy-dns` |
| v4 | `./modules/easy-dns/modules/dns/v4` |

Keep the directory together: the wrappers use the shared core module through a relative path. The Cloudflare provider is still installed from the Terraform Registry on `terraform init`; for fully offline use, set up a provider mirror with `terraform providers mirror`. `modules/easy-dns/VERSION` shows the version of the copy; to upgrade, replace the directory with the archive of the new version and follow [Upgrading and Migration](#upgrading-and-migration).

#### In a Larger Repository

Each release also has a provider v5 archive, `terraform-cloudflare-easy-dns-v5-<version>.tar.gz` (in the same `SHA256SUMS`): the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and without `migrate-from-v4.tf`, the `moved` block for configurations that used the v4 wrapper. It is meant for repositories that pin provider v5 and run tools over every directory, where the v4 wrapper's `~> 4.41` would conflict. Updating such a copy is a plain replacement of the directory.

What a copy may change without affecting the module:

- `versions.tf` (root and `modules/dns/v5`) may be replaced by the repository's own pin, as long as it allows Terraform `>= 1.8.0` and the Cloudflare provider `>= 5.26` within v5
- `schema/` is only needed for records in YAML, and the `README.md` files of the submodules are generated reference
- With the full archive and no history on provider v4: `modules/dns/v4` and `modules/dns/v5/migrate-from-v4.tf` may be dropped, which gives the v5 archive

### Git Source

To fetch the module on `terraform init` instead, use a Git source with a tag (or the URL of your own mirror):

```hcl
source = "git::https://github.com/i386dev/terraform-cloudflare-easy-dns.git?ref=v2.10.2"
```

For provider v4, add `//modules/dns/v4` before `?ref=`. In CI, where every run starts from a clean checkout, add `&depth=1` after the tag (`?ref=v2.10.2&depth=1`) to fetch only that commit instead of the whole history.

### HCL or YAML

Records can be written directly in `records` or kept in a YAML file passed through `yamldecode`. The module validates both the same way at `plan`; only YAML gets completion and highlighting of mistakes in the editor, through the [JSON Schema](#records-in-yaml):

| | Records in HCL | Records in YAML |
|:-|:-|:-|
| Completion and mistakes highlighted in the editor | no (Terraform provides none inside `records`) | yes, with the JSON Schema |
| Validation at `plan` (typos, types, IP addresses, `data` fields, ...) | yes | yes |

### Full Example

A zone with most of the features: the apex, nested names, aliases, CAA and a structured SRV record.

```hcl
module "dns" {
  source = "./modules/easy-dns"

  zone_id   = var.zone_id
  zone_name = "example.com" # optional, looked up from zone_id when omitted

  records = {
    # Zone apex (example.com)
    "@" = {
      A = [
        { content = "30.40.50.61", proxied = true },
      ]
      # Result: TXT record for _dmarc.example.com
      "_dmarc.TXT" = [
        { content = "v=DMARC1; p=none" },
      ]
      # An explicit key keeps the record in place when the value changes
      "google._domainkey.TXT" = [
        { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
      ]
      # Result: www.example.com -> CNAME -> example.com
      ALIASES = [
        { content = "www", proxied = true },
      ]
    }

    # This will manage records for app.example.com
    "app" = {
      A = [
        { content = "30.40.50.60", proxied = true },
      ]
      # Aliases create CNAMEs pointing to 'app.example.com'
      # Result: support.example.com -> CNAME -> app.example.com
      ALIASES = [
        { content = "support", ttl = 1800 },
      ]
      TXT = [
        { content = "v=spf1 include:_spf.google.com ~all" },
      ]
      MX = [
        { content = "mail.example.com", priority = 1 },
      ]
      CAA = [
        { content = "letsencrypt.org", tag = "issue" },
        { content = "letsencrypt.org", tag = "issuewild" },
      ]
      # Supports specific sub-keys.
      # Result: TXT record for _acme-challenge.app.example.com
      "_acme-challenge.TXT" = [
        { content = "verification-token" },
      ]
      # Inline aliases point to a prefixed name.
      # Result: static.example.com -> CNAME -> cdn.app.example.com
      "cdn.ALIASES" = [
        { content = "static" },
      ]
    }

    # Structured records use data instead of content
    # Result: SRV record for _sip._tcp.example.com
    "_sip._tcp" = {
      SRV = [{
        data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
      }]
    }
  }
}
```

Complete runnable configurations are available in [`examples`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/examples): `v5` (records in HCL), `yaml` (records in a YAML file), `import` (adopting an existing zone) and `v4` (provider v4, for existing configurations).

## Record Model

The module flattens the input map into a single map with a unique key for each record, which is then used in `for_each`.

### Record Types and Nested Names
Each key inside a base name block is a record type (`A`, `AAAA`, `CNAME`, `TXT`, `MX`, `CAA`, `SRV`, ...; see [Record Types](#record-types)). A key with a dot-notation (like `"_acme-challenge.TXT"`) is split: the last part is the record type, everything before it is prepended to the base name. Inside the `@` block the prefix becomes the record name itself (`"_dmarc.TXT"` becomes `_dmarc.example.com`).

### Record Types

Most records are defined by `content`. Structured records are defined by a `data` map instead, with the same fields as in the Cloudflare API. The module only checks which fields are present; what the fields and their values mean is described in the Cloudflare [DNS record types](https://developers.cloudflare.com/dns/manage-dns-records/reference/dns-record-types/) and in the `data` attribute of [`cloudflare_dns_record`](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record), as are `settings`:

| Type | Defined by | `data` fields (optional in italics) |
|------|-----------|--------------------------------------|
| `A`, `AAAA`, `CNAME`, `NS`, `PTR`, `TXT` | `content` | - |
| `MX` | `content`, `priority` | - |
| `OPENPGPKEY` | `content` | - (provider v5 only) |
| `CAA` | `content`, `tag`, `flags` | - |
| `SRV` | `data` | `priority`, `weight`, `port`, `target` |
| `URI` | `data`, `priority` | `weight`, `target` |
| `HTTPS`, `SVCB` | `data` | `priority`, `target`, *`value`* |
| `TLSA`, `SMIMEA` | `data` | `usage`, `selector`, `matching_type`, `certificate` |
| `SSHFP` | `data` | `algorithm`, `type`, `fingerprint` |
| `DS` | `data` | `key_tag`, `algorithm`, `digest_type`, `digest` |
| `DNSKEY` | `data` | `flags`, `protocol`, `algorithm`, `public_key` |
| `CERT` | `data` | `type`, `key_tag`, `algorithm`, `certificate` |
| `NAPTR` | `data` | `order`, `preference`, `replacement`, *`flags`*, *`service`*, *`regex`* |
| `LOC` | `data` | `lat_degrees`, `lat_minutes`, `lat_seconds`, `lat_direction`, `long_degrees`, `long_minutes`, `long_seconds`, `long_direction`, *`altitude`*, *`size`*, *`precision_horz`*, *`precision_vert`* |

The service and protocol of `SRV`, `URI` and `TLSA` records are part of the name:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
"mail" = {
  "_25._tcp.TLSA" = [{
    key  = "mx"
    data = { usage = 3, selector = 1, matching_type = 1, certificate = "..." }
  }]
}
```

### The `ALIASES` Logic
When you define `ALIASES` inside a block (e.g., inside `"app"`), the module creates a `CNAME` record for each entry where:
- **Name**: The value provided in `content` (e.g., `support` for support.example.com).
- **Target**: The base name plus the zone domain (e.g., `app.example.com`, or `example.com` for `@`).

A base name may be short (`app`) or fully qualified (`app.example.com`): the target is the same fully qualified name, and `@` or the zone name point to the zone apex.

### Inline Aliases
A key like `"cdn.ALIASES"` works the same way, but the target is the prefixed name: `cdn.app.example.com` (or `cdn.example.com` for `@`).

### Record Keys
Each record is keyed in the state by its content, in the zone file format `<name> <TYPE> <value>`, so adding, removing or reordering items in a list affects only those items:

| Record | Key |
|--------|-----|
| `A`, `AAAA`, `MX`, `NS`, `PTR` | `app A 30.40.50.60`, `@ MX mail.example.com` |
| `TXT` | `_dmarc TXT 21541c4e7044` (first 12 characters of the SHA-1 of the value) |
| Records with `data` (`SRV`, `TLSA`, ...) | `_sip._tcp SRV 9c61601f99e8` (first 12 characters of the SHA-1 of the data) |
| `CNAME` and `ALIASES` | `www CNAME` (only one CNAME is allowed per name) |
| `CAA` | `app CAA issue letsencrypt.org` |
| Any record with `key` | `google._domainkey TXT dkim` |

```
module.dns.cloudflare_record.record["app A 30.40.50.60"]
```

Since the value is a part of the key, changing it replaces the record. For values that change over time (e.g. DKIM rotation or a server IP), set an explicit `key`, so the record is updated in place:

```hcl
"google._domainkey.TXT" = [
  { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
]
```

#### When to Use `key`

Use a `key` whenever the value of a record is expected to change, or is not known until `apply`:

- DKIM keys and other rotated values
- ACME challenge tokens and service verification records
- server IPs that change, e.g. after a migration
- values from other resources (`content = aws_instance.web.public_ip`)
- `MX` records that differ only in priority, `CAA` records that differ only in flags

Without a `key`, a changed value is a new record: the old one is deleted and the new one created.

**Values computed by other resources need a `key`.** `for_each` keys must be known at `plan`, so a record whose value comes from another resource (`content = aws_instance.web.public_ip`) fails with "The "for_each" value depends on resource attributes that cannot be determined until apply" unless it has a `key`:

```hcl
"web" = {
  A = [{ key = "web", content = aws_instance.web.public_ip }]
}
```

Two records that produce the same key (e.g. the same value listed twice, or a `CNAME` and an alias with the same name) fail at `plan` with the list of duplicates and where each of them is defined. `MX` records that differ only in `priority` and `CAA` records that differ only in `flags` get the same key too, since neither is a part of it; give each of them a `key`:

```hcl
MX = [
  { content = "mx.example.net", priority = 10, key = "primary" },
  { content = "mx.example.net", priority = 20, key = "backup" },
]
```

Names are sent to Cloudflare in lower case, as Cloudflare stores them; the key keeps the name as written (`M1._domainkey TXT dkim`).

**Rewriting a name in another form changes its key.** `www`, `WWW` and `www.example.com` are the same DNS name, but the key keeps the form as written, so changing it (`www` to `www.example.com`, or `WWW` to `www`) gives the record a new address, and Terraform plans to delete and create it. To keep the existing record, add a `moved` block with the old and the new key, then check that the plan neither deletes nor creates it:

```hcl
moved {
  from = module.dns.module.v5.cloudflare_dns_record.record["www A 192.0.2.10"]
  to   = module.dns.module.v5.cloudflare_dns_record.record["www.example.com A 192.0.2.10"]
}
```

With the `//modules/dns/v5` submodule, the address has no `module.v5`; with the v4 wrapper, the resource is `cloudflare_record.record`.

## Validation

The `records` input is validated before any API call. The module checks the structure and invariants that hold for every zone; protocol-specific values (SRV port ranges, DNSKEY algorithms, LOC coordinates, ...) are left to the Cloudflare API:

- Record attributes must be known: a misspelled attribute such as `proxid = true` fails with `records["app"]["A"][0]: unknown attribute "proxid"` instead of being ignored, and the same for `settings`

- Supported record types: see [Record Types](#record-types), plus `ALIASES` (with an optional prefix, e.g. `"_acme-challenge.TXT"`)
- Records defined by `content` must have a non-empty `content`
- Structured records must have `data` with only the fields of their type and all required ones; other records must not set `data`
- `ttl` and `default_ttl` must be `1` (automatic) or between `minimum_ttl` and `86400`. `minimum_ttl` is `60` by default: Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, where it can be set to `30`. A lower TTL, and a `default_ttl` below `minimum_ttl` even if no record uses it, fail at `plan` with what to change; proxied records always get `1`
- Only `A`, `AAAA`, `CNAME` and `ALIASES` records can be `proxied`
- `MX` and `URI` records require `priority`
- `A` records need an IPv4 address and `AAAA` records an IPv6 address; `CNAME`, `MX`, `NS` and `PTR` records need a hostname: labels of letters, digits, `_` and `-` (up to 63 characters) separated by dots, at most 253 characters, an optional trailing dot, and not an IP address (`@` stands for the zone apex, and `.` is a null `MX`, RFC 7505)
- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records must be a hostname by the same rule, or `.` (no service for `SRV`, the owner name for `HTTPS` and `SVCB`, no replacement for `NAPTR`). `@` is not accepted there: the module passes `data` to Cloudflare as written. `URI` targets are URIs and are not checked
- `TXT` values are limited to 2048 characters
- Names, prefixes and `ALIASES` must be valid DNS names: labels of letters, digits, `_` and `-` separated by dots. Internationalized names, also in `zone_name`, must be given in Punycode (`xn--mnchen-3ya` for `münchen`), as the Cloudflare API expects them
- A wildcard `*` must be the whole leftmost label, also in the names a prefix and a base name combine into (`"_acme-challenge.TXT"` under `"*"` would give `_acme-challenge.*`) and in the targets of `<prefix>.ALIASES`
- A `CNAME` or alias cannot point to its own name (case, a trailing dot, `@` and the short form do not matter)
- `CAA` records require `tag`: `issue`, `issuewild` or `iodef`
- `key` must not contain whitespace
- Record keys must be unique. The error shows where each duplicate is defined, e.g. `"_acme-challenge.app TXT 79bead8e6d65" from records["_acme-challenge.app"]["TXT"][0] and records["app"]["_acme-challenge.TXT"][0]`
- The same record must not be written twice with different name forms (`www` and `www.example.com`, `@` and the zone name), which would give it two keys; addresses and hostnames (`A`, `AAAA`, `MX`, `NS`, `PTR`) are compared case-insensitively and without a trailing dot
- A `CNAME` (including `ALIASES`) cannot share its name with other records, except at the zone apex (`@` or the zone name) where Cloudflare uses CNAME flattening, and a name has at most one `CNAME`, also with different `key`s. Names are compared fully qualified, so `www` and `www.example.com` are the same name
- **Migration escape hatch for legacy zones:** existing zones may have names where a `CNAME` shares its name with other records, which Cloudflare accepts for records that are not proxied. Such names can be listed in `allowed_cname_conflicts` (compared fully qualified and case-insensitively), so the zone can be adopted without changing live DNS first. Only the listed names are exempt: a conflict on any other name still fails, a second `CNAME` on a listed name still fails, and a listed name that has no conflict anymore shows a warning so the list can shrink:

  ```hcl
  allowed_cname_conflicts = ["community", "*.legacy"]
  ```

  The listed names must be valid names, written like the names in `records`.

## Inputs

Both wrappers take `zone_id`, `zone_name` (optional, looked up from `zone_id` when omitted; when set, it must be the name of that zone, see [Requirements](#requirements)), `records`, the [defaults](#defaults-comments-and-tags), `minimum_ttl` and `allowed_cname_conflicts` (see [Validation](#validation)); the v5 wrapper also takes `import_existing`.

The type of `records` is shown as `any`: Terraform silently drops unknown attributes when it converts a value to an object type, so the module accepts the value as is, rejects unknown attributes, and then converts it to the typed structure described in [Record Object Schema](#record-object-schema). The full reference of inputs, outputs, requirements and resources is generated from the code with [terraform-docs](https://terraform-docs.io): [`modules/dns/v4`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/modules/dns/v4), [`modules/dns/v5`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/modules/dns/v5).

### Record Object Schema

| Field | Description | Default |
|-------|-------------|---------|
| `content` | IP address, hostname, or text value | `null` |
| `ttl` | Time to Live (automatically set to `1` if proxied) | `default_ttl` (`3600`) |
| `proxied` | Whether the record gets Cloudflare's proxy | `default_proxied` (`false`) for `A`, `AAAA`, `CNAME` and `ALIASES`, otherwise `false` |
| `priority` | Priority for MX and URI records | `null` |
| `tag` | Tag for CAA records (`issue`, `issuewild`, `iodef`) | `null` |
| `flags` | Flags for CAA records | `0` |
| `data` | Fields of structured records, see [Record Types](#record-types) | `null` |
| `key` | Stable key used instead of the value in the record key, see [Record Keys](#record-keys) | `null` |
| `comment` | Note shown in the Cloudflare dashboard | `default_comment` |
| `tags` | Tags such as `owner:web`, added to `default_tags` | `[]` |
| `settings` | `flatten_cname`, `ipv4_only` and `ipv6_only` (provider v5 only, ignored by the v4 wrapper) | `null` |

### Defaults, Comments and Tags

Values that most records share can be set once for the module call, and overridden per record:

| Input | Description | Default |
|-------|-------------|---------|
| `default_ttl` | TTL of records that do not set one | `3600` |
| `default_proxied` | Proxying of `A`, `AAAA`, `CNAME` and `ALIASES` records that do not set `proxied` (other types are never proxied) | `false` |
| `default_comment` | Comment of records that do not set one | `null` |
| `default_tags` | Tags added to the tags of every record | `[]` |

```hcl
module "dns" {
  source = "./modules/easy-dns"

  zone_id         = var.zone_id
  zone_name       = "example.com"
  default_proxied = true
  default_comment = "Managed by Terraform"
  default_tags    = ["managed-by:terraform"]

  records = {
    # Proxied, with the default comment and tags
    "@" = { A = [{ content = "192.0.2.10" }] }

    "vpn" = {
      A = [{ content = "192.0.2.20", proxied = false, comment = "WireGuard" }]
    }
  }
}
```

Cloudflare supports record tags only on some plans and limits the length of comments by plan, see [DNS record comments and tags](https://developers.cloudflare.com/dns/manage-dns-records/reference/record-attributes/); on other plans, leave `default_tags` and `tags` empty.

## Outputs

- `record_names`: names of all managed records
- `records`: managed records keyed by their [record key](#record-keys), with `id`, `name`, `type` and `content`
- `state_migration`: map of the record keys used by 1.x to the current ones, see [Upgrading from v1](#from-v1-to-v2)
- `import_ids` (v5): import IDs of records that already exist in the zone, see [Importing Existing Records](#importing-existing-records)
- `import_duplicates` (v5): records that match several existing records in the zone, with the IDs of the matches; they are not imported

## Records in YAML

Records can be kept in a YAML file and passed with `yamldecode`:

```hcl
records = yamldecode(file("${path.module}/records.easy-dns.yaml")).records
```

`schema/records.schema.json` is a JSON Schema for such a file (a document with a `records` key). Editors use it for completion of record types, attributes and `data` fields, and highlight mistakes such as `proxid`, `ttl: 5m` or a CAA `tag` that does not exist before `terraform plan`. With a [local copy](#local-copy), the schema is at `modules/easy-dns/schema/records.schema.json`.

Name the files `*.easy-dns.yaml` (e.g. `records.easy-dns.yaml`) and map this pattern to the schema once:

- **JetBrains IDEs**: Settings, Languages & Frameworks, Schemas and DTDs, JSON Schema Mappings: add the schema file with the file path pattern `*.easy-dns.yaml`.
- **VS Code** (with the YAML extension): in the workspace settings,

  ```json
  "yaml.schemas": {
    "./modules/easy-dns/schema/records.schema.json": "*.easy-dns.yaml"
  }
  ```

Alternatively, a comment at the top of a file links the schema regardless of its name (the path is relative to the file):

```yaml
# yaml-language-server: $schema=modules/easy-dns/schema/records.schema.json
```

See [`examples/yaml`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/examples/yaml).

Use the schema of the module version you use. For records written in HCL, there is no such completion (see [HCL or YAML](#hcl-or-yaml)); mistakes are reported at `plan`.

**Quote text values.** `yamldecode` follows YAML 1.1, where unquoted `off`, `on`, `yes`, `no`, `N` and `Y` are booleans and `0123` or `1.10` are numbers; Terraform would turn them into `"false"`, `"123"` or `"1.1"` without an error. The module rejects booleans in `content`, `key`, `comment` and `tag`, and warns about numbers there. Quoted, they stay as written:

```yaml
TXT:
  - content: "off"     # not: content: off  ->  "false"
  - content: "0123"    # not: content: 0123 ->  "123"
```

`yamldecode` follows YAML 1.1, where unquoted `yes`, `no`, `on`, `off`, `y` and `n` (in any case) are booleans; quote such values, e.g. `content: "on"`. The module accepts the unquoted `N` of a LOC `lat_direction`.

## Recipes

### A Record Type or Field the Module Does Not Support

Record types and attributes are a closed list, so misspelled ones fail at `plan`. When Cloudflare adds something the module does not know yet, manage that record with the provider resource next to the module call, in the same zone:

```hcl
resource "cloudflare_dns_record" "special" {
  zone_id = var.zone_id
  name    = "special"
  type    = "TXT"
  content = "..."
  ttl     = 1
  # any argument the provider supports
}
```

Keep it out of `records`, so the record is not managed twice. Once the module supports it, move it into `records` with a `moved` block to its key.

Mail with SPF, DKIM and DMARC; the DKIM record has a `key`, so rotating the key updates the record in place:

```hcl
"@" = {
  MX = [
    { content = "mx1.mail.example.net", priority = 10 },
    { content = "mx2.mail.example.net", priority = 20 },
  ]
  TXT = [{ content = "v=spf1 include:_spf.mail.example.net -all" }]

  "google._domainkey.TXT" = [
    { key = "dkim", content = "v=DKIM1; k=rsa; p=MIIBIjANBg..." },
  ]
  "_dmarc.TXT" = [
    { content = "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com" },
  ]
}
```

A website behind the Cloudflare proxy, with `www` pointing to the apex:

```hcl
"@" = {
  A       = [{ content = "192.0.2.10", proxied = true }]
  ALIASES = [{ content = "www", proxied = true }]
}
```

Certificate authority restrictions and the ACME DNS challenge of a certificate for `app.example.com`:

```hcl
"@" = {
  CAA = [
    { content = "letsencrypt.org", tag = "issue" },
    { content = "letsencrypt.org", tag = "issuewild" },
    { content = "mailto:security@example.com", tag = "iodef" },
  ]
}
"app" = {
  A                     = [{ content = "192.0.2.30" }]
  "_acme-challenge.TXT" = [{ key = "acme", content = "challenge-token" }]
}
```

A service advertised with SRV:

```hcl
"_sip._tcp" = {
  SRV = [{
    data = { priority = 10, weight = 5, port = 5060, target = "sip.example.com" }
  }]
}
```

## Importing Existing Records

When the zone already has records, the first `apply` would fail with "record already exists" for each of them. With provider v5 (the root module or the `v5` submodule), the module can find the existing records and adopt them into the state instead. It works the same with records in HCL or in YAML; see [`examples/import`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/examples/import).

> **`import_existing` does not import anything by itself.** It only finds the IDs of existing records and exposes them in `import_ids`; the `import` block in step 2 does the import. It is not a reconciliation either: records of the zone that are not in `records` are left alone.

Each lookup reads up to 10,000 records of one type; in a zone with more records of a configured type, the rest are not found and would be created again. `plan` shows a warning when a lookup returns 10,000 records; import the remaining records with `import` blocks of their own.

1. Set `import_existing = true`. The module then reads the records of the zone (the API token needs the `DNS Read` permission) and matches them to the configured records by name, type and value. The records are read with one request per record type of the configuration, which avoids a provider crash on zones with CAA records ([cloudflare/terraform-provider-cloudflare#7004](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004)).
2. Add an `import` block next to the module call:

   ```hcl
   import {
     for_each = module.dns.import_ids
     to       = module.dns.module.v5.cloudflare_dns_record.record[each.key]
     id       = each.value
   }
   ```

   With the `//modules/dns/v5` submodule, the address has no `module.v5`: `module.dns.cloudflare_dns_record.record[each.key]`.

3. Run `terraform plan`. Existing records are shown as imported, and only records missing in the zone are created. Check that no record you expect to be imported is shown as created.
4. Run `terraform apply`, then remove the `import` block and `import_existing`, so the zone is not read on every plan.

For structured records (`SRV`, `HTTPS`, `TLSA`, ...), provider v5 plans a one-time in-place update right after the import, without visible changes; after the `apply`, the plan is empty.

Matching ignores the case and a trailing dot of names, hostnames (`target`, `replacement`, the issuer domain of CAA `issue`/`issuewild` values) and hex values (`digest`, `fingerprint`, and `certificate` of TLSA and SMIMEA records); other `data` fields, CAA parameters after `;`, `iodef` URLs and OPENPGPKEY keys must match exactly. TXT values are compared without the split into quoted chunks; a value in the zone file form (`"v=spf1 \"a\" -all"`) is compared without its surrounding quotes and escapes, since Cloudflare stores TXT content as it was sent and `v=spf1 "a" -all` is the same DNS record; quotes inside the value count. A TXT record stored in the quoted form and configured without quotes gets a one-time in-place update to the configured form after the import (the DNS answer does not change). A record is imported only when exactly one existing record matches it: when the zone has several identical records, the record is not imported and `plan` shows it as created, so the duplicates can be cleaned up first. Such records are listed in the `import_duplicates` output with the IDs of all their matches, and `plan` shows a warning with the same list; [`examples/import`](https://github.com/i386dev/terraform-cloudflare-easy-dns/tree/main/examples/import) passes the output through so it shows up in `plan`.

## Upgrading and Migration

### Upgrade Path

Do one step at a time, each with its own `terraform plan` and `apply`, and review every plan: it must not destroy or create records.

1. **From v1 to v2** (record keys): [v1 to v2](#from-v1-to-v2), staying on the submodule you already use. Targeting 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) as part of this step.
2. **From provider v4 to v5**, if you use the `v4` submodule: [provider v4 to v5](#from-provider-v4-to-v5).
3. **To the root module**, optionally: [v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module).

Configurations that use the module from the Terraform Registry switch to a local copy or a Git source, see [from the Terraform Registry](#from-the-terraform-registry).

For example, a configuration on `//modules/dns/v5` of v1 does step 1 with `RESOURCE=cloudflare_dns_record` and may stay on the submodule. From 2.0–2.5, upgrading to 2.6 or later only needs the [unknown attributes](#to-26-unknown-attributes) fixed, if there are any.

### From v1 to v2

Version 2 changes the record keys in the state (see [Record Keys](#record-keys)). Without migration, Terraform would destroy and recreate every record. The `state_migration` output maps the old keys to the new ones, so the migration can be done with `moved` blocks:

1. Change the module to version 2.x (replace the local copy, or change `?ref=` of a Git source), keeping the same submodule (`//modules/dns/v4` or `//modules/dns/v5`), and run `terraform init -upgrade`. With 2.6 or later, fix any [unknown attributes](#to-26-unknown-attributes) first, otherwise `terraform console` in the next step fails.
2. Generate `moved` blocks (requires `jq`). Set `MODULE` to the module address and `RESOURCE` to `cloudflare_record` for the `v4` submodule or `cloudflare_dns_record` for the `v5` submodule (version 1 had no root module):

   ```sh
   MODULE=module.dns
   RESOURCE=cloudflare_record
   echo "jsonencode(${MODULE}.state_migration)" | terraform console \
     | jq -r --arg addr "$MODULE.$RESOURCE.record" '
         fromjson | to_entries[] |
         "moved {",
         "  from = \($addr)[\(.key | tojson)]",
         "  to   = \($addr)[\(.value | tojson)]",
         "}", ""' \
     > dns_migration.tf
   ```

3. Run `terraform plan`. It should only show records that have moved, with no records to add or destroy.
4. Run `terraform apply`, then delete `dns_migration.tf`. The next `terraform plan` should show no changes.

### To 2.8: Minimum TTL

> **Enterprise zones with TTLs from 30 to 59 seconds:** set `minimum_ttl = 30` in the module call before upgrading, or the plan fails.

TTLs below 60 seconds (other than `1`, automatic) are rejected at `plan` unless `minimum_ttl = 30`. Cloudflare accepts them only on Enterprise zones, so on other plans such a TTL already failed at the API; now the plan says what to change. The module cannot see the plan of a zone without an extra API call, hence the explicit setting.

### To 2.7: Names in Lower Case

Record names are sent in lower case, as Cloudflare stores them. With provider v5, a name written in another case (`M1._domainkey`) showed a change on every plan that `apply` did not settle; that diff is gone. With the v4 wrapper, such a record gets a one-time in-place update of its name. Keys keep the name as written, so no state address changes.

### To 2.6: Unknown Attributes

Since 2.6, a record attribute that the module does not know fails the plan, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`. Before, Terraform silently dropped such attributes, so a misspelled optional attribute had no effect. Fix the reported attributes: the plan then shows whether the corrected attributes change any records (e.g. a record that was meant to be proxied). For records in YAML, the [JSON Schema](#records-in-yaml) highlights these mistakes in the editor.

### From Provider v4 to v5

The v5 wrapper contains a `moved` block from `cloudflare_record` to `cloudflare_dns_record`, so the state is migrated without recreating records:

1. Upgrade the Cloudflare provider to `~> 5.26`.
2. Change the module `source` from `//modules/dns/v4` to `//modules/dns/v5`, keeping the module name the same. To go straight to the root module, also add the `moved` block from [the v5 submodule to the root module](#from-the-v5-submodule-to-the-root-module), with `cloudflare_record` in `from`.
3. Run `terraform init -upgrade` and `terraform plan`. The plan should only show moved resources, without destroying or creating records; provider v5 also plans a one-time in-place update of the moved records (e.g. CAA `flags` become numbers). Review it carefully before applying.
4. Run `terraform apply`. Provider v5 (checked with 5.26) may report `Provider produced inconsistent result after apply` with `.modified_on` for some records: the timestamp in the migrated state has a different precision ([cloudflare/terraform-provider-cloudflare#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)). The records are updated anyway; run `terraform plan` again, it should show no changes.

### From the Terraform Registry

The module was published on the Terraform Registry as `NikitaPuglachenko/easy-dns/cloudflare` and is no longer available there. Use a [local copy](#local-copy) or a [Git source](#git-source) of the same version instead, keeping the module name and the path (root module or `//modules/dns/v4`, `//modules/dns/v5`): the module is the same, so no addresses in the state change. Remove `version`, run `terraform init -upgrade`, and `terraform plan` shows no changes.

### From the v5 Submodule to the Root Module

The root module wraps the v5 submodule, so its records have one more level in their address. When switching `source` from the `v5` submodule (`./modules/easy-dns/modules/dns/v5` or `//modules/dns/v5` in a Git source) to the root module, add a `moved` block next to the module call, so the records are not recreated:

```hcl
moved {
  from = module.dns.cloudflare_dns_record.record
  to   = module.dns.module.v5.cloudflare_dns_record.record
}
```

Run `terraform init -upgrade` and `terraform plan`: it should only show records that have moved. After `terraform apply`, the `moved` block can be removed. Staying on the submodule is fine as well.

## Testing

The core module, both wrappers and the examples have plan-only tests (the wrappers and examples use a mocked provider), no Cloudflare credentials needed. The core module's tests also pin the invariants of name normalization (`names.tftest.hcl`: every form of a name gives one fully qualified name) and record identity (`identity.tftest.hcl`: reordering records keeps their keys, a `key` keeps the address when the value changes, YAML and HCL give the same records):

```sh
cd modules/dns/v5
terraform init
terraform test
```

The module READMEs are generated with [terraform-docs](https://terraform-docs.io), and the JSON Schema with a script that reads the record types and `data` fields from the records module. After changing variables, outputs, requirements or record types, regenerate them:

```sh
./scripts/generate-docs.sh
python3 scripts/generate-schema.py
python3 scripts/test-schema.py   # requires jsonschema and pyyaml
python3 scripts/test-schema.py --terraform   # the same documents through the module: schema and validation must agree
```

CI runs `terraform fmt`, `validate` and `test` for the root module, the core module, both wrappers and the examples (on Terraform 1.8 and the latest version, and on the minimum supported provider versions), checks that the module READMEs and the JSON Schema are up to date, tests the schema, checks that the root module and the wrappers have the same interface, [TFLint](https://github.com/terraform-linters/tflint) and [Gitleaks](https://github.com/gitleaks/gitleaks) on every pull request.

### End-to-End Tests

`tests/e2e/run.sh` runs against a real Cloudflare zone. Under a label of the run (e.g. `e2e-1234.example.com`), it:

1. Creates records of every type through the root module and checks that a second `plan` shows no changes (no drift in the provider).
2. Changes values: a record without a `key` is replaced, a record with a `key` is updated in place.
3. Adopts the same records into an empty state with `import_existing` and checks that all of them are imported, none created, and each one under the ID of the record created in step 1.
4. Creates records with the v4 wrapper and opens the state with the v5 wrapper: the records must be moved, not recreated, and keep their keys and Cloudflare IDs.
5. Deletes everything. `tests/e2e/sweep.sh` also removes records left by failed runs; it only deletes records with the comment `easy-dns-e2e` and a run label in the name.

```sh
CLOUDFLARE_API_TOKEN=... E2E_ZONE_ID=... E2E_ZONE_NAME=example.com tests/e2e/run.sh
```

The token needs the `DNS Edit` permission on the zone. In CI, the test runs weekly and on demand (never for pull requests), with the token stored in the `cloudflare-e2e` environment.

## License
MIT

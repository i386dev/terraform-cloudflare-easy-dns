# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [2.11.1] - 2026-10-04

### Fixed

- IPv6 addresses written in another form (`2001:0db8:0:0:0:0:0:1` for `2001:db8::1`, upper case) were not recognized as the same address: two such records passed the duplicate check (the API rejects the second), and with `import_existing` such a record did not match the existing one, which Cloudflare stores in the canonical form. Addresses are now compared in the canonical form and sent in it; keys keep the address as written, so no state address changes. A record written in another form may get a one-time in-place update of its content to the canonical form
- With `import_existing`, a TXT value with `" "` inside (`prefix" "suffix`) matched an existing record without it (`prefixsuffix`), since every `" "` was removed before comparing. Only values in the zone file form (one or more quoted chunks) are now joined from their chunks, without the escapes `\"` and `\\`; other values are compared exactly

### Internal

- Tests: an IPv6 address in two forms (duplicate), sent in the canonical form (core, both wrappers), an IPv4-mapped address, import of an address in another form, TXT with `" "` inside (no false match, same value matches), quoted chunks with escaped quotes and backslashes, other escapes kept (`\065`)
- The end-to-end fixture writes its AAAA record in a non-canonical form, to check against the API that it causes no drift and is matched on import (passed on this branch)
- The lookup limit of `import_existing` still has no automated test: the mocked provider cannot return the nested `result` list of `cloudflare_dns_records`

## [2.11.0] - 2026-10-04

### Changed

- **With `import_existing`, an ambiguous or incomplete import stops the plan** instead of showing a warning. An ambiguous match (several identical records in the zone, or records that differ only in priority without an existing record of the same priority) used to plan the record as created, which the API rejects at apply or which leaves two copies of it; a lookup that returned 10,000 records (the limit) used to miss the records beyond it. The plan now fails with the list of records (or the record type) and what to do: remove the duplicates from the zone, give the records distinct values or priorities, or set `import_existing = false` and use `import` blocks for these records. Configurations without such records are not affected. The `import_duplicates` output stays, with the same content

### Added

- With `import_existing`, a record with a priority (MX, URI) that matches several existing records takes the one with its priority: a zone with MX 10 and MX 20 on one host and the configuration with both now imports both (before, neither was imported)

### Internal

- Tests: ambiguous matches stop the plan (identical records in the zone, the same priority twice, no record of the configured priority), several matches resolved by priority; the lookup limit was checked against a real zone with the limit lowered to 1 (the plan stops, and the saved plan is not applyable)

## [2.10.4] - 2026-10-04

### Fixed

- With `import_existing`, one existing record could be imported into two addresses: configured records that differ only in `priority` (MX `primary` and `backup` with the same server) both matched the one MX record in the zone, and both got its ID. An existing record now goes to one address only: to the record with the same priority, while the others are created; without such a record, none of them is imported, and they are listed in `import_duplicates` with the plan warning
- Fractional TTLs (`ttl = 60.5`, `default_ttl = 3600.5`) and priorities passed the validation, which the JSON schema rejects; TTLs and priorities must now be whole numbers, priorities from 0 to 65535 (also in the JSON schema)
- The length of the fully qualified name was not checked: a prefix, a name and the zone that are valid on their own could combine into more than 253 characters, also in the target of a prefixed `ALIASES`; such names and targets now fail at `plan`
- `tags` given as a set in HCL (`toset([false])`, `toset([123])`) skipped the checks for booleans and numbers, which looked tags up by index

### Changed

- The release workflow builds the archives and the GitHub release only after CI passed for the tagged commit (it waits for a CI run that is still in progress); the tag itself is available to Git sources as soon as it is pushed

### Internal

- Tests: one existing record and records that differ in priority (matching, other and unknown priority), fractional TTL, `default_ttl` and priority, priority over 16 bits, names of 253 and 267 characters and an alias target of 267, sets of tags; schema parity documents for fractional TTL and priority, priorities out of range and a name over 253 characters

## [2.10.3] - 2026-10-04

### Fixed

- Internationalized zones: Cloudflare returns the name of such a zone in Unicode (`münchen.de`), while record names come back in Punycode, so a zone looked up by `zone_id` failed at `plan` with "The zone name must be a DNS name". The lookup now fails with a message to set `zone_name` in Punycode (`xn--mnchen-3ya.de`), and the error for a non-ASCII `zone_name` added in 2.10.2 no longer suggests leaving it unset (root module and both wrappers)
- Unquoted YAML booleans in `tags` and in the fields of `data` (`value: off`, `tags: [yes]`) were sent as `"false"` and `"true"`; they are now rejected like in `content`, `key`, `comment` and `tag`. In YAML, quote them. The unquoted `N` of a LOC `lat_direction` is still accepted
- Unquoted YAML numbers in `tags` and in the text fields of `data` (`digest: 0123` is sent as `"123"`) now show the same warning as in `content`, `key`, `comment` and `tag`; numeric fields such as `port` or `priority` may still be numbers
- An explicit `null` for `default_ttl`, `default_proxied` or `default_tags` failed with unclear errors; `null` now means the default (root module, both wrappers)
- With `import_existing`, the `target` of URI records was compared case-insensitively, so a record could be matched to one whose path differs only in case; it is now compared exactly
- A null `MX` (`"."`) with a priority other than 0 was accepted; RFC 7505 defines it with preference 0, and the module and the JSON schema now require it

### Changed

- README: internationalized zones need `zone_name` in Punycode; the record address in Record Keys is the one of the root module; "DNS name" instead of "hostname" in the validation rules, as in the errors; `key` must be non-empty; the two paragraphs about YAML booleans are merged; `null` defaults

### Internal

- CI checks the SHA256 of the downloaded `terraform-docs`
- `scripts/check-sync.sh` compares all variables of the v4 and v5 wrappers (except `import_existing`) and their check of text values, not only `records`
- Tests: Unicode and Punycode zone names (lookup and core), booleans and numbers in `data` and `tags`, the unquoted `N` of LOC, `null` defaults, null `MX` priority, exact URI target in import matching; schema parity documents for null `MX`, booleans in `data` and `tags`

## [2.10.2] - 2026-10-04

### Fixed

- A `zone_name` with non-ASCII characters (`münchen.de`) failed with the general "must be the DNS name of the zone" error; it now gets its own error that asks for Punycode (`xn--mnchen-3ya.de`) or an unset `zone_name` (root module and both wrappers)

### Changed

- README: `zone_name` must also be given in Punycode
- README: rewriting a record name in another form (`www` to `www.example.com`, `WWW` to `www`) changes its key and recreates the record unless a `moved` block keeps it

### Internal

- Tests: a Unicode `zone_name` in the root module and both wrappers

## [2.10.1] - 2026-10-03

### Fixed

- A `zone_name` with a trailing dot (`"example.com."`, as in zone files) broke the fully qualified names used by the checks and by import matching (`app.example.com` was taken for `app.example.com.example.com.`, so it was not found in the zone and not compared with `app`), and alias targets got the dot (`example.com.`); the trailing dot is now ignored. Record names sent to Cloudflare were not affected; an alias created with such a `zone_name` gets a one-time in-place update of its target
- An empty `zone_name` failed with an unclear error in `coalesce()`; `zone_name` is now validated as a DNS name (root module and both wrappers)
- `allowed_cname_conflicts` accepted any string, and a misspelled name never matched; the names are now validated like the names in `records`

### Added

- With `import_existing`, `plan` warns when the lookup of a record type returns 10,000 records (the limit): records beyond it are not found and would be planned as new

### Internal

- Tests: zone names with a trailing dot and in another case, empty and invalid zone names, invalid and fully qualified `allowed_cname_conflicts`, one lookup per record type with `import_existing`

## [2.10.0] - 2026-10-03

### Changed

- Validation errors of `records` list every record that fails, with its path and value: `records["app"]["CAA"][0]: tag "isue"`, `records["_sip._tcp"]["SRV"][0].data: missing field "port"`, `records["web"]["CNAME"][0]: "192.0.2.1"`; before, the message only named the rule
- The JSON Schema checks hostnames like the module: `content` of `CNAME`, `MX`, `NS` and `PTR` records and `target`/`replacement` of `SRV`, `HTTPS`, `SVCB` and `NAPTR` records (labels, at most 253 characters, not an IP address; `@`, and `.` where the module allows it). Editors now flag such values before `plan`
- README: when not to use the module

### Internal

- The core module is split into `names.tf`, `keys.tf` and `checks.tf`, with an overview in `main.tf`
- Tests of record identity (reordering keeps keys, `key` keeps the address when the value changes, keys are case-sensitive, YAML and HCL give the same records), TTL boundaries, wildcard positions, names with a trailing dot and Punycode
- `scripts/test-schema.py --terraform` runs the schema test documents through the module, so the schema and the validation must accept and reject the same documents; CI runs it
- The end-to-end test checks that imported and migrated records keep their Cloudflare IDs

## [2.9.0] - 2026-10-03

### Added

- `import_duplicates` output (root module, v5 wrapper): records that match several existing records in the zone when `import_existing` is set, keyed by record key, with the Cloudflare IDs of the matches. These records are not imported, and `plan` shows a warning listing them
- Release archives have signed build provenance (`gh attestation verify <archive> --repo i386dev/terraform-cloudflare-easy-dns --signer-workflow i386dev/terraform-cloudflare-easy-dns/.github/workflows/release.yml`)

### Changed

- `target` of `SRV`, `HTTPS` and `SVCB` records and `replacement` of `NAPTR` records are validated as hostnames, like `CNAME`, `MX`, `NS` and `PTR` values, or `.`; values with spaces, invalid characters, an IP address or `@` fail at `plan` instead of at the Cloudflare API

## [2.8.2] - 2026-10-03

### Fixed

- A wildcard could end up outside the leftmost label when names combine: a prefix under a wildcard base name (`"_acme-challenge.TXT"` under `"*"` gave `_acme-challenge.*`, `"x.A"` under `"*.app"` gave `x.*.app`) and the target of `<prefix>.ALIASES` under a wildcard base name; such names now fail at `plan`
- A `CNAME` or alias pointing to its own name (`"app" = { ALIASES = [{ content = "app" }] }`, `www CNAME www.example.com.`, `@ CNAME @`) fails at `plan`
- A `default_ttl` below `minimum_ttl` fails at `plan` also when no record uses it

### Changed

- Error messages say "DNS name" instead of "hostname" for `CNAME`, `MX`, `NS` and `PTR` values
- README: a table of the `records` keys up front; `zone_name` must match `zone_id` (the module cannot check it); when to use `key`; `import_existing` only finds IDs and reads up to 10,000 records per type; Punycode for internationalized names; `allowed_cname_conflicts` as a migration escape hatch; what the validation covers and what it leaves to the API; "Structured Records" instead of "All Record Types"

## [2.8.1] - 2026-10-03

### Fixed

- Unquoted YAML 1.1 booleans (`off`, `on`, `yes`, `no`, `N`, `Y`) in `content`, `key`, `comment` or `tag` were turned into `"false"`/`"true"` without an error; they now fail at `plan` with the record and a hint to quote them. Numbers there (`0123` -> `"123"`, `1.10` -> `"1.1"`) show a warning

### Changed

- README: values computed by other resources need a `key`; `&depth=1` for Git sources in CI; managing a record type or field the module does not support next to the module call; quoting text values in YAML

## [2.8.0] - 2026-10-03

### Changed

- **TTLs below 60 seconds need `minimum_ttl = 30`.** The new `minimum_ttl` input (root module, both wrappers; `60` by default, `30` for Enterprise zones) is the lowest TTL other than `1` (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones, so on other plans they failed at the API; now the plan fails with what to change. Enterprise zones that use TTLs from 30 to 59 seconds must set `minimum_ttl = 30` when upgrading

### Fixed

- `ALIASES` under a fully qualified base name (`"app.example.com"`) pointed to `app.example.com.example.com`, and `"cdn.ALIASES"` to `cdn.app.example.com.example.com`; alias targets now use the same fully qualified name as every other check, so a short and a fully qualified base name give the same target. Configurations that used short base names plan no change
- Import matching (`import_existing`) did not find existing records under a fully qualified base name
- `CNAME`, `MX`, `NS` and `PTR` values are validated as hostnames (labels of letters, digits, `_` and `-`, at most 253 characters, not an IP address; `@` for the apex, `.` for a null `MX`); before, only `CNAME` was checked, and only for not being an IP address, so values with spaces or invalid characters failed at the Cloudflare API

## [2.7.0] - 2026-10-01

### Added

- `allowed_cname_conflicts` input (root module, both wrappers): names where a `CNAME` may share its name with other records, for existing zones where Cloudflare accepted it for records that are not proxied. Names are compared fully qualified and case-insensitively; only the listed names are exempt, a second `CNAME` on a name still fails, and a listed name without a conflict shows a warning
- A provider v5 release archive, `terraform-cloudflare-easy-dns-v5-<version>.tar.gz`: the root module, `modules/dns/v5` and `modules/dns/records`, without the v4 wrapper and its migration `moved` block, for copies in repositories that pin provider v5
- README: what a copy in a larger repository may replace or drop

### Fixed

- Record names are sent in lower case, as Cloudflare stores them: with provider v5, a name in another case showed a change on every plan. Keys keep the name as written, so no state address changes; with the v4 wrapper, such a record gets a one-time in-place update of its name

### Changed

- The duplicate error explains that `MX` records differing only in priority and `CAA` records differing only in flags need a `key`; the CNAME error points to `allowed_cname_conflicts`
- The `moved` block from the v4 wrapper is in `modules/dns/v5/migrate-from-v4.tf`, so a v5-only copy can leave it out

## [2.6.4] - 2026-10-01

### Fixed

- Import matching with `import_existing` no longer drops quotes inside TXT values or compares every `data` field case-insensitively, which could match a different existing record (a TXT value differing only in inner quotes, a NAPTR `regex` or a public key differing in case); hostnames and hex values are still compared case-insensitively
- Import matching treats a TXT value in the zone file form (`"v=spf1 \"a\" -all"`) as the same record as its unquoted form (`v=spf1 "a" -all`), as Cloudflare serves them identically; before, such a record was not adopted and `apply` failed with "record already exists"
- Import matching compares the issuer domain of CAA `issue`/`issuewild` values case-insensitively again (the parameters after `;` and `iodef` URLs exactly), and OPENPGPKEY keys exactly instead of lower-cased
- Two or more `CNAME`s on one name are rejected also when they have different `key`s
- The same record written with different name forms (`www` and `www.example.com`, `@` and the zone name) is rejected as a duplicate at `plan` instead of failing at `apply`; addresses and hostnames are compared case-insensitively and without a trailing dot
- The CNAME checks compare names fully qualified: a `CNAME` on the zone name is accepted next to other records like one on `@`, and `www` and `www.example.com` are the same name

## [2.6.3] - 2026-09-29

### Added

- Releases include an archive of the module (`terraform-cloudflare-easy-dns-<version>.tar.gz`, with a `VERSION` file) and `SHA256SUMS`, to keep a local copy of the module in a configuration

### Changed

- The module is not published on the Terraform Registry: the README describes a local copy of the module (without GitHub or the Registry on `terraform init`) and a Git source, and how to switch from the Registry source; the examples, the YAML schema setup (a local schema file) and the upgrade guide follow this

### Removed

- The Terraform Registry badge and the temporary Registry note

## [2.6.2] - 2026-09-27

### Changed

- README: a note that the module cannot be downloaded from the Terraform Registry as `i386dev/easy-dns/cloudflare` yet, with the Git source to use until it is republished

## [2.6.1] - 2026-09-27

### Changed

- The repository moved to [i386dev/terraform-cloudflare-easy-dns](https://github.com/i386dev/terraform-cloudflare-easy-dns) and the module to the Registry source `i386dev/easy-dns/cloudflare`; the README, examples, badges and the schema `$id` use the new addresses, and the README describes switching `source` from `NikitaPuglachenko/easy-dns/cloudflare`
- CI runs the gitleaks CLI instead of the gitleaks action, which requires a license for organizations

## [2.6.0] - 2026-09-26

### Added

- JSON Schema `schema/records.schema.json` for records kept in YAML, for completion and validation in editors; it is generated from the records module and tested in CI, also against the module through `yamldecode`
- Examples `examples/yaml` (records in `records.easy-dns.yaml`, checked by the schema in CI) and `examples/import` (adopting an existing zone)
- Unknown record attributes fail at `plan` with the record and the attribute, e.g. `records["app"]["A"][0]: unknown attribute "proxid"`, also inside `settings`; before, Terraform silently dropped them, so a misspelled optional attribute was ignored

### Fixed

- A LOC record from YAML with an unquoted `lat_direction: N` failed, since `yamldecode` reads it as `false`; it is now read as `N`

### Changed

- `examples/v5` uses the root module, like the Registry source
- README: HCL or YAML compared, links to the Cloudflare documentation of record types, `data`, `settings`, comments and tags; a table of contents, the detailed "How It Works" is now "Record Model", and the upgrade and migration guides are one section with the order of the steps and a guide for unknown attributes when upgrading to 2.6
- The `records` input of the root module and the wrappers has the type `any`, so unknown attributes reach the check; the record schema is in the input description and the README, and the records module still converts the value to the typed structure

## [2.5.3] - 2026-09-26

### Fixed

- README layout on the Terraform Registry: badges on one line, code examples narrow enough to fit without being cut off, and the state address table with short keys

## [2.5.2] - 2026-09-26

### Changed

- README: a short introduction to the input model with a minimal example and the resulting state addresses, before the full example

## [2.5.1] - 2026-09-26

### Changed

- The workarounds for provider v5 issues link to them: the per-type lookup of existing records ([#7004](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7004)) and the `modified_on` error after the v4 to v5 migration ([#7387](https://github.com/cloudflare/terraform-provider-cloudflare/issues/7387)), so they can be removed once the issues are fixed

## [2.5.0] - 2026-09-26

### Added

- `default_ttl`, `default_proxied`, `default_comment` and `default_tags` inputs, overridable per record
- `comment` and `tags` per record; `settings` (`flatten_cname`, `ipv4_only`, `ipv6_only`) per record for provider v5
- Validation of IPv4 addresses in `A`, IPv6 addresses in `AAAA`, hostnames in `CNAME`, the length of `TXT` values and DNS names of base names, prefixes and `ALIASES`
- End-to-end tests against a real Cloudflare zone: every record type, drift, updates, import and the v4 to v5 migration; run weekly and on demand
- CI tests on the minimum supported provider versions
- Releases are created from the changelog when a tag is pushed
- README: badges, recipes, a deprecation note for the v4 wrapper

### Fixed

- Import failed with a Terraform crash when the zone had CAA or DNSKEY records together with other types: provider v5 returns `data.flags` with different types in one list, so existing records are now looked up per record type
- SVCB and HTTPS records showed a change on every plan: Cloudflare returns their `target` with a trailing dot, which is now added
- The v4 wrapper required provider `~> 4.30`, but `cloudflare_record` has the `content` attribute only since 4.39; the minimum is now `~> 4.41`, which also fixes the handling of `content` and `value` in the state

## [2.4.0] - 2026-09-26

### Added

- Root module wrapping the v5 wrapper, so `source = "NikitaPuglachenko/easy-dns/cloudflare"` works as shown on the Terraform Registry; the submodules are unchanged
- CI check that the root module and the wrappers have the same inputs and outputs

### Changed

- README and examples use the Terraform Registry source; links point to GitHub, so they work on the Registry page
- README describes switching from the v5 submodule to the root module with a `moved` block

## [2.3.0] - 2026-09-26

### Added

- Import of records that already exist in the zone (provider v5): `import_existing` input and `import_ids` output for an `import` block with `for_each`

## [2.2.0] - 2026-09-26

### Added

- A `CNAME` (including `ALIASES`) sharing its name with other records fails at `plan`, except at the zone apex
- Module READMEs with inputs, outputs, requirements and resources generated by terraform-docs; CI checks that they are up to date

### Changed

- Duplicate record errors show where each duplicate is defined in `records`
- The main README links to the generated reference instead of maintaining the input and output tables by hand

## [2.1.0] - 2026-09-26

### Added

- Record types `SRV`, `URI`, `HTTPS`, `SVCB`, `TLSA`, `SMIMEA`, `SSHFP`, `DS`, `DNSKEY`, `CERT`, `NAPTR` and `LOC` through the new `data` field, and `OPENPGPKEY` (provider v5)
- Validation of `data` fields for each record type
- `URI` records require `priority`

### Changed

- Wrapper tests cover only the mapping to the provider resource; record parsing is tested in the core module

## [2.0.0] - 2026-09-26

### Changed

- **Breaking:** records are keyed in the state by their content in the zone file format (`app A 30.40.50.60`, `www CNAME`, `_dmarc TXT 21541c4e7044`) instead of their position in the list, so adding, removing or reordering items no longer recreates other records. Existing states must be migrated, see "Upgrading from v1" in the README

### Added

- Optional `key` field to keep a record in place when its value changes
- Duplicate record keys fail at `plan` with the list of duplicates
- `state_migration` output mapping the 1.x keys to the new ones, used to generate `moved` blocks

## [1.1.0] - 2026-09-26

### Added

- Validation of the `records` input: supported record types, non-empty `content`, TTL range, `proxied` only for `A`/`AAAA`/`CNAME`/`ALIASES`, `priority` for `MX`, `tag` for `CAA`
- `records` output with `id`, `name`, `type` and `content` of each managed record
- Complete examples for provider v4 and v5 in `examples/`
- Tests for the core module and the examples
- Dependabot updates for GitHub Actions

### Changed

- README usage example starts with the zone apex (`@`)

## [1.0.0] - 2026-09-26

### Added

- Provider-agnostic core module `modules/dns/records`
- `modules/dns/v4` wrapper for Cloudflare provider v4 (`cloudflare_record`)
- `modules/dns/v5` wrapper for Cloudflare provider v5 (`cloudflare_dns_record`) with a `moved` block for migration from v4
- Optional `zone_name` input, looked up from `zone_id` when omitted
- Plan-only tests with a mocked provider
- CI: `terraform fmt`, `validate`, `test`, TFLint and Gitleaks

### Fixed

- The locals file was not loaded by Terraform
- Hardcoded root domain replaced with `zone_name` or a zone lookup
- Defaults for `ttl`, `proxied` and `flags` were `null` instead of the documented values
- Inline aliases pointed to a relative name instead of the full hostname
- Zone apex (`@`) handling for aliases and nested names

[Unreleased]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.11.1...HEAD
[2.11.1]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.11.0...v2.11.1
[2.11.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.10.4...v2.11.0
[2.10.4]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.10.3...v2.10.4
[2.10.3]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.10.2...v2.10.3
[2.10.2]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.10.1...v2.10.2
[2.10.1]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.10.0...v2.10.1
[2.10.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.8.2...v2.9.0
[2.8.2]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.8.1...v2.8.2
[2.8.1]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.8.0...v2.8.1
[2.8.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.6.4...v2.7.0
[2.6.4]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.6.3...v2.6.4
[2.6.3]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.6.2...v2.6.3
[2.6.2]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.6.1...v2.6.2
[2.6.1]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.6.0...v2.6.1
[2.6.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.5.3...v2.6.0
[2.5.3]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.5.2...v2.5.3
[2.5.2]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.5.1...v2.5.2
[2.5.1]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.5.0...v2.5.1
[2.5.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/i386dev/terraform-cloudflare-easy-dns/releases/tag/v1.0.0

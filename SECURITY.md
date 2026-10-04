# Security Policy

## Supported Versions

Fixes go into the latest release. Older versions do not get backports: upgrade to the latest 2.x release, see [Upgrading and Migration](README.md#upgrading-and-migration).

| Version | Supported |
|---------|-----------|
| Latest 2.x release | Yes |
| Older 2.x releases, 1.x | No |

## Reporting a Vulnerability

Do not open a public issue. Report it privately through [GitHub private vulnerability reporting](https://github.com/i386dev/terraform-cloudflare-easy-dns/security/advisories/new) with:

- the affected version and wrapper (root module, `modules/dns/v4`, `modules/dns/v5`);
- the configuration that shows the problem (without real tokens or zone IDs);
- what happens and what you expected.

You get an answer within 7 days. When the report is confirmed, the fix is released with a GitHub security advisory that credits you, unless you ask not to be named.

## Scope

In scope:

- The module code: for example, records created in another zone or under another name than configured, records deleted or replaced that the configuration does not change, or validation that lets through a value it is meant to reject.
- The release archives and their build provenance.
- The GitHub Actions workflows of this repository.

Out of scope: bugs of the Cloudflare provider, the Cloudflare API and Terraform itself. Report them to their projects.

## Verifying Releases

Each release archive has a checksum in `SHA256SUMS` and signed build provenance, see [Local Copy](README.md#local-copy). From 2.10.4, the release workflow publishes a tag only after CI passed for the tagged commit:

```sh
gh attestation verify terraform-cloudflare-easy-dns-<version>.tar.gz \
  --repo i386dev/terraform-cloudflare-easy-dns \
  --signer-workflow i386dev/terraform-cloudflare-easy-dns/.github/workflows/release.yml
```

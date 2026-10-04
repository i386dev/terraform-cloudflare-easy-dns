# Records core

Provider-agnostic core used by the provider wrappers in `modules/dns`: validates the `records` input and flattens it into a map of records keyed by `<name> <TYPE> <value>`. It has no provider dependency and is not meant to be used directly. See the [main README](https://github.com/i386dev/terraform-cloudflare-easy-dns#readme) for the input format.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |

## Providers

No providers.

## Modules

No modules.

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cname_conflicts"></a> [allowed\_cname\_conflicts](#input\_allowed\_cname\_conflicts) | Names where a CNAME may share its name with other records, for existing zones that have such names (Cloudflare accepts them for records that are not proxied). Compared fully qualified and case-insensitively; a second CNAME on a name still fails | `list(string)` | `[]` | no |
| <a name="input_default_comment"></a> [default\_comment](#input\_default\_comment) | Comment of records that do not set one, e.g. "Managed by Terraform" | `string` | `null` | no |
| <a name="input_default_proxied"></a> [default\_proxied](#input\_default\_proxied) | Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare | `bool` | `false` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags added to all records, e.g. ["managed-by:terraform"] (tags require a Cloudflare plan that supports them) | `list(string)` | `[]` | no |
| <a name="input_default_ttl"></a> [default\_ttl](#input\_default\_ttl) | TTL of records that do not set one (1 means automatic) | `number` | `3600` | no |
| <a name="input_existing_records"></a> [existing\_records](#input\_existing\_records) | Records that already exist in the zone, used to find import IDs and unmanaged records. Names are fully qualified, as returned by the Cloudflare API | <pre>list(object({<br/>    id       = string<br/>    name     = string<br/>    type     = string<br/>    content  = optional(string)<br/>    priority = optional(number)<br/>    data     = optional(map(string))<br/>  }))</pre> | `[]` | no |
| <a name="input_import_existing"></a> [import\_existing](#input\_import\_existing) | Whether existing\_records are matched to the configured records for import. When false, they are only compared to report unmanaged records | `bool` | `true` | no |
| <a name="input_minimum_ttl"></a> [minimum\_ttl](#input\_minimum\_ttl) | Lowest TTL other than 1 (automatic): 60 seconds on every Cloudflare plan, 30 only on Enterprise zones | `number` | `60` | no |
| <a name="input_records"></a> [records](#input\_records) | DNS records grouped by base name (subdomain or @ for apex), then by record type | <pre>map(<br/>    map(<br/>      list(<br/>        object({<br/>          content  = optional(string)<br/>          ttl      = optional(number) # default_ttl when not set<br/>          proxied  = optional(bool)   # default_proxied when not set<br/>          priority = optional(number)<br/><br/>          # for CAA<br/>          tag   = optional(string)<br/>          flags = optional(number, 0)<br/><br/>          # Structured data for SRV, URI, HTTPS, SVCB, TLSA, SMIMEA, SSHFP, DS, DNSKEY, CERT, NAPTR and LOC<br/>          data = optional(map(string))<br/><br/>          # Stable key instead of the record value, so changing the value updates the record in place<br/>          key = optional(string)<br/><br/>          # Shown in the Cloudflare dashboard: comment replaces default_comment, tags are added to default_tags<br/>          comment = optional(string)<br/>          tags    = optional(list(string))<br/><br/>          # Record settings (Cloudflare provider v5)<br/>          settings = optional(object({<br/>            flatten_cname = optional(bool)<br/>            ipv4_only     = optional(bool)<br/>            ipv6_only     = optional(bool)<br/>          }))<br/>        })<br/>      )<br/>    )<br/>  )</pre> | n/a | yes |
| <a name="input_root_domain"></a> [root\_domain](#input\_root\_domain) | Zone domain name (e.g. example.com), used as the target suffix for aliases. A trailing dot is ignored | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_ambiguous_matches"></a> [ambiguous\_matches](#output\_ambiguous\_matches) | Configured records that match several existing records or share one with other configured records, keyed by record key, also without import\_existing (import\_duplicates is empty then) |
| <a name="output_flat_records"></a> [flat\_records](#output\_flat\_records) | Flattened map of records keyed by "<name> <TYPE> <value>", ready for for\_each |
| <a name="output_import_duplicates"></a> [import\_duplicates](#output\_import\_duplicates) | Cloudflare record IDs of existing\_records that a configured record cannot be matched to unambiguously, keyed by record key. While there are any, import\_record\_ids fails and the plan stops |
| <a name="output_import_record_ids"></a> [import\_record\_ids](#output\_import\_record\_ids) | Cloudflare record IDs of existing\_records matching the configured records, keyed by record key. Records with no match are left out; ambiguous matches stop the plan (see import\_duplicates) |
| <a name="output_state_migration"></a> [state\_migration](#output\_state\_migration) | Map of record keys used by module versions 1.x to the current keys, for state migration |
| <a name="output_unmanaged_records"></a> [unmanaged\_records](#output\_unmanaged\_records) | existing\_records that no configured record matches: records in the zone that the configuration does not describe. Sensitive: the content of a proxied record is the origin address that Cloudflare hides |
<!-- END_TF_DOCS -->

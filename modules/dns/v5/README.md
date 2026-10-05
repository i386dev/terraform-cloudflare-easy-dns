# DNS records for Cloudflare provider v5

Manages DNS records with `cloudflare_dns_record`. See the [main README](https://github.com/i386dev/terraform-cloudflare-easy-dns#readme) for usage, record types, keys and migration.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.8.0 |
| <a name="requirement_cloudflare"></a> [cloudflare](#requirement\_cloudflare) | ~> 5.26 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_cloudflare"></a> [cloudflare](#provider\_cloudflare) | ~> 5.26 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_records"></a> [records](#module\_records) | ../records | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [cloudflare_dns_record.record](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record) | resource |
| [cloudflare_dns_records.existing](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/dns_records) | data source |
| [cloudflare_zone.this](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/data-sources/zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_cname_conflicts"></a> [allowed\_cname\_conflicts](#input\_allowed\_cname\_conflicts) | Names where a CNAME already shares its name with other records in the zone, e.g. ["community", "*.legacy.example.com"]. Cloudflare accepts this for records that are not proxied, and older zones often have such names; only the listed names are exempt from the CNAME check. Compared fully qualified and case-insensitively; a second CNAME on a name still fails, and listed names without a conflict show a warning | `list(string)` | `[]` | no |
| <a name="input_default_comment"></a> [default\_comment](#input\_default\_comment) | Comment of records that do not set one, e.g. "Managed by Terraform" | `string` | `null` | no |
| <a name="input_default_proxied"></a> [default\_proxied](#input\_default\_proxied) | Whether A, AAAA, CNAME and ALIASES records that do not set proxied are proxied by Cloudflare | `bool` | `false` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Tags added to all records, e.g. ["managed-by:terraform"] (tags require a Cloudflare plan that supports them) | `list(string)` | `[]` | no |
| <a name="input_default_ttl"></a> [default\_ttl](#input\_default\_ttl) | TTL of records that do not set one (1 means automatic) | `number` | `3600` | no |
| <a name="input_import_existing"></a> [import\_existing](#input\_import\_existing) | Look up records that already exist in the zone and expose their IDs in the import\_ids output, to adopt them with import blocks. Requires the DNS Read permission | `bool` | `false` | no |
| <a name="input_minimum_ttl"></a> [minimum\_ttl](#input\_minimum\_ttl) | Lowest TTL other than 1 (automatic). Cloudflare accepts TTLs below 60 seconds only on Enterprise zones: set 30 there, keep 60 otherwise | `number` | `60` | no |
| <a name="input_records"></a> [records](#input\_records) | DNS records: `records[NAME][TYPE] = [RECORD, ...]`, where NAME is a name within the<br/>zone (`@` for the apex) and TYPE a record type, optionally with a prefix<br/>(`"_acme-challenge.TXT"`). Record attributes: `content`, `ttl`, `proxied`, `priority`,<br/>`tag`, `flags`, `data`, `key`, `comment`, `tags` and `settings` (`flatten_cname`,<br/>`ipv4_only`, `ipv6_only`). See the README for the details. Unknown attributes fail at plan. | `any` | n/a | yes |
| <a name="input_report_unmanaged"></a> [report\_unmanaged](#input\_report\_unmanaged) | Look up the records of all types in the zone and report those that the configuration does not describe, in the unmanaged\_records output and a plan warning. Nothing is deleted. Requires the DNS Read permission (one request per record type) | `bool` | `false` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Cloudflare Zone ID | `string` | n/a | yes |
| <a name="input_zone_name"></a> [zone\_name](#input\_zone\_name) | Zone domain name (e.g. example.com). If null, it is looked up from zone\_id. A trailing dot is ignored. Internationalized zones must set it, in Punycode | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_import_duplicates"></a> [import\_duplicates](#output\_import\_duplicates) | Cloudflare record IDs of existing records that a configured record cannot be matched to unambiguously, keyed by record key. Empty unless import\_existing is true; while there are any, the plan stops with this list |
| <a name="output_import_ids"></a> [import\_ids](#output\_import\_ids) | Import IDs (<zone\_id>/<record\_id>) of records that already exist in the zone, keyed by record key. Empty unless import\_existing is true; records with no match are left out, and ambiguous matches stop the plan |
| <a name="output_record_names"></a> [record\_names](#output\_record\_names) | Names of all managed records |
| <a name="output_records"></a> [records](#output\_records) | Managed records keyed by their stable identifier, with id, name, type and content |
| <a name="output_state_migration"></a> [state\_migration](#output\_state\_migration) | Map of record keys used by module versions 1.x to the current keys, for state migration |
| <a name="output_unmanaged_records"></a> [unmanaged\_records](#output\_unmanaged\_records) | Records in the zone that the configuration does not describe (id, name, type, content, priority, data). Empty unless report\_unmanaged is true. Sensitive: the content of a proxied record is the origin address that Cloudflare hides |
<!-- END_TF_DOCS -->

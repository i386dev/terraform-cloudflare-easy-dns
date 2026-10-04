# Root module for the Terraform Registry: the provider v5 wrapper.
# For provider v4, use the modules/dns/v4 submodule.
module "v5" {
  source = "./modules/dns/v5"

  zone_id                 = var.zone_id
  zone_name               = var.zone_name
  records                 = var.records
  import_existing         = var.import_existing
  report_unmanaged        = var.report_unmanaged
  default_ttl             = var.default_ttl
  default_proxied         = var.default_proxied
  default_comment         = var.default_comment
  default_tags            = var.default_tags
  allowed_cname_conflicts = var.allowed_cname_conflicts
  minimum_ttl             = var.minimum_ttl
}

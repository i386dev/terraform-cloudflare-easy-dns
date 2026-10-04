# Scenario 1: all record types through the root module

module "fixture" {
  source = "../fixture"

  prefix    = var.prefix
  zone_name = var.zone_name
  a_value   = var.a_value
  txt_value = var.txt_value
}

module "dns" {
  source = "../../.."

  zone_id          = var.zone_id
  zone_name        = var.zone_name
  default_ttl      = 300
  default_comment  = "easy-dns-e2e"
  report_unmanaged = var.report_unmanaged
  records          = module.fixture.records
}

module "lake" {
  source = "./modules/lake"

  grupo          = var.grupo
  trusted_prefix = var.trusted_prefix
  teto_bytes     = var.teto_bytes
}

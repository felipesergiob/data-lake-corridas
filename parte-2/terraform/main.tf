module "admin_lf" {
  source = "./modules/admin-lf"

  regiao = var.regiao
}

module "lake" {
  source = "./modules/lake"

  grupo         = var.grupo
  teto_bytes    = var.teto_bytes
  anos_projecao = var.anos_projecao

  depends_on = [module.admin_lf]
}

module "acesso" {
  source = "./modules/acesso"

  grupo                     = var.grupo
  regiao                    = var.regiao
  bucket_arns               = module.lake.bucket_arns
  databases                 = module.lake.databases
  tabelas                   = module.lake.tabelas
  tabela_ids                = module.lake.tabela_ids
  workgroup_arn             = module.lake.workgroup_arn
  athena_results_bucket_arn = module.lake.athena_results_bucket_arn

  depends_on = [module.lake]
}

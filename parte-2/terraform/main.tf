module "lake" {
  source = "./modules/lake"

  grupo         = var.grupo
  teto_bytes    = var.teto_bytes
  anos_projecao = var.anos_projecao
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
  gerenciar_admins_lf       = var.gerenciar_admins_lf
  admins_lf_extras          = var.admins_lf_extras

  depends_on = [module.lake]
}

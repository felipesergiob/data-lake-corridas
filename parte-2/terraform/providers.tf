provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      turma   = var.turma
      grupo   = var.grupo
      projeto = var.projeto
    }
  }
}

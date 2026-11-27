# Backend parcial: dados da conta ficam no backend.hcl local, nao versionado.
terraform {
  backend "s3" {
    workspace_key_prefix = "eda262-g11"
  }
}

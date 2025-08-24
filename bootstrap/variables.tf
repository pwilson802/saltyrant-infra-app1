variable "region" { type = string }
variable "env" { type = string }
variable "repo_owner" { type = string }
variable "repo_name" { type = string }

variable "enable_kms" {
  type    = bool
  default = true
}

variable "allowed_environments" {
  type    = list(string)
}

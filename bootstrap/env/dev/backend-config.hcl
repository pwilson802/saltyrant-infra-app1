# terraform {
#   backend "s3" {
#     bucket = "dev-deadman-tfstate-193086214415"
#     key    = "infra/bootstrap/terraform.tfstate"
#     region = "ap-southeast-2"
#   }
# }
path = "env/dev/terraform.tfstate"
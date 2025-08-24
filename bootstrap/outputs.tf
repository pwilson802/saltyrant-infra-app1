output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "state_bucket_arn" { value = aws_s3_bucket.state.arn }
output "role_arn" { value = aws_iam_role.tf_gh.arn }
output "kms_key_arn" { value = try(aws_kms_key.tf[0].arn, null) }
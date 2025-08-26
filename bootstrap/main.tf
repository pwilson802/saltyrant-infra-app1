provider "aws" { region = var.region }

data "aws_caller_identity" "me" {}
data "aws_partition" "part" {}

locals {
  bucket_name = "${var.env}-salty-tfstate-${data.aws_caller_identity.me.account_id}"
  role_name   = "salty-tf-github-oidc-${var.env}"
  readonly_role_name   = "salty-tf-github-oidc-readonly-${var.env}"
  key_alias   = "alias/${var.env}-tfstate"
  repo_full   = "${var.repo_owner}/${var.repo_name}"
}

resource "aws_kms_key" "tf" {
  count                   = var.enable_kms ? 1 : 0
  description             = "CMK for Terraform state (${var.env})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
resource "aws_kms_alias" "tf" {
  count         = var.enable_kms ? 1 : 0
  name          = local.key_alias
  target_key_id = aws_kms_key.tf[0].key_id
}

# State bucket
resource "aws_s3_bucket" "state" { bucket = local.bucket_name }

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms ? aws_kms_key.tf[0].arn : null
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}



# GitHub OIDC provider (safe to create if missing)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Role for GH Actions
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repo_owner}/${var.repo_name}:environment:${var.env}"]
    }
  }
}
resource "aws_iam_role" "tf_gh" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  description          = "GitHub OIDC role for ${var.env}"
  max_session_duration = 3600
}

# Minimal perms: state + .tflock (+ KMS if used)
data "aws_iam_policy_document" "tf_perms" {
  statement {
    sid       = "StateList"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    sid       = "StateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
  dynamic "statement" {
    for_each = var.enable_kms ? [1] : []
    content {
      sid       = "KmsForState"
      effect    = "Allow"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = [aws_kms_key.tf[0].arn]
    }
  }
}
resource "aws_iam_policy" "tf" {
  name   = "SaltyRant-TF-State-${var.env}"
  policy = data.aws_iam_policy_document.tf_perms.json
}

resource "aws_iam_role_policy_attachment" "attach" {
  role       = aws_iam_role.tf_gh.name
  policy_arn = aws_iam_policy.tf.arn
}

# ReadOnly Role for GH Actions
data "aws_iam_policy_document" "assume-readonly" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.repo_owner}/${var.repo_name}:environment:${var.env}-plan"]
    }
  }
}

resource "aws_iam_role" "tf_gh_readonly" {
  name                 = local.readonly_role_name
  assume_role_policy   = data.aws_iam_policy_document.assume-readonly.json
  description          = "GitHub OIDC role for ${var.env}"
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "attach_realonly" {
  role       = aws_iam_role.tf_gh_readonly.name
  policy_arn = aws_iam_policy.tf.arn
}

resource "aws_iam_role_policy_attachment" "readonly_managed" {
  role       = aws_iam_role.tf_gh_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

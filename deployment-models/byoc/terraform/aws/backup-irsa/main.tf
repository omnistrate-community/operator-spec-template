# Per-instance IAM role for CloudNativePG / Barman Cloud backups (IRSA).
# Runs in the customer's AWS account (BYOC data plane). No static AWS keys:
# the Barman sidecar in each Postgres pod assumes this role with the pod's
# projected service account token. Trust is limited to service accounts in
# this instance's namespace, and access is limited to the backup bucket.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  issuer_raw = trimprefix(var.oidc_issuer_id, "https://")
  issuer_from_id = var.oidc_issuer_id == "" ? "" : (
    length(regexall("/", local.issuer_raw)) > 0
    ? local.issuer_raw
    : "oidc.eks.${var.region}.amazonaws.com/id/${local.issuer_raw}"
  )
}

data "aws_eks_cluster" "cell" {
  count = local.issuer_from_id == "" ? 1 : 0
  name  = var.eks_cluster_name
}

locals {
  oidc_host = local.issuer_from_id != "" ? local.issuer_from_id : replace(data.aws_eks_cluster.cell[0].identity[0].oidc[0].issuer, "https://", "")
  partition = data.aws_partition.current.partition
  account   = data.aws_caller_identity.current.account_id
  role_name = substr("cnpg-backup-${var.instance_id}", 0, 64)
  bucket    = "arn:${local.partition}:s3:::${var.bucket_name}"
}

resource "aws_iam_role" "backup" {
  name                 = local.role_name
  description          = "CNPG Postgres BYOC backups for ${var.instance_id}"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:${local.partition}:iam::${local.account}:oidc-provider/${local.oidc_host}" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "${local.oidc_host}:aud" = "sts.amazonaws.com" }
        StringLike   = { "${local.oidc_host}:sub" = "system:serviceaccount:*${var.instance_id}:*" }
      }
    }]
  })

  tags = {
    "omnistrate.com/instance"   = var.instance_id
    "omnistrate.com/managed-by" = "omnistrate"
    "purpose"                   = "cnpg-barman-backups"
  }
}

resource "aws_iam_role_policy" "backup" {
  name = "cnpg-backup-s3"
  role = aws_iam_role.backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketLevel"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = local.bucket
      },
      {
        Sid      = "ObjectLevel"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${local.bucket}/*"
      },
      {
        Sid      = "KmsViaS3"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = "*"
        Condition = {
          StringEquals = { "kms:ViaService" = "s3.${var.region}.amazonaws.com" }
        }
      }
    ]
  })
}

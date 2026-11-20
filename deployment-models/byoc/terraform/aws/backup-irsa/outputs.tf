output "role_arn" {
  description = "IAM role ARN the CNPG service account assumes for S3 backups."
  value       = aws_iam_role.backup.arn
}

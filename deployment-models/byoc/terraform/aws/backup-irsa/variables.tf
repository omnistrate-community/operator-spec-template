variable "instance_id" {
  description = "Omnistrate instance ID. The instance namespace is derived from it and scopes the role trust."
  type        = string
}

variable "region" {
  description = "AWS region of the deployment cell."
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name of the deployment cell. Used to look up the OIDC issuer when oidc_issuer_id is empty."
  type        = string
  default     = ""
}

variable "oidc_issuer_id" {
  description = "OIDC issuer ID (or full issuer URL) of the deployment cell's EKS cluster."
  type        = string
  default     = ""
}

variable "bucket_name" {
  description = "Customer-owned S3 bucket that stores the Barman base backups and WAL archive."
  type        = string
}

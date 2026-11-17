variable "region" {
  description = "AWS region for the source bucket and DataSync resources. The destination bucket is expected to be in the same region."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name the IAM role, log group and DataSync task."
  type        = string
  default     = "datasync-s3-xacct"

  validation {
    condition     = can(regex("^[A-Za-z0-9+=,.@_-]{1,40}$", var.name_prefix))
    error_message = "name_prefix must be 1-40 characters of letters, digits or +=,.@_-."
  }
}

variable "source_bucket_name" {
  description = "Name of the new source S3 bucket created in this account."
  type        = string
}

variable "destination_bucket_name" {
  description = "Name of the third party's destination S3 bucket."
  type        = string
}

variable "destination_account_id" {
  description = "AWS account ID that owns the destination bucket."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.destination_account_id))
    error_message = "destination_account_id must be a 12-digit AWS account ID."
  }
}

variable "destination_kms_key_arn" {
  description = "ARN of the third party's KMS key if the destination bucket uses SSE-KMS. Leave null for SSE-S3."
  type        = string
  default     = null

  validation {
    condition     = var.destination_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:", var.destination_kms_key_arn))
    error_message = "destination_kms_key_arn must be a KMS key ARN or null."
  }
}

variable "location_creator_permission_set_name" {
  description = <<-EOT
    Optional. IAM Identity Center permission set name (e.g. "AdministratorAccess") you run the CLI under.
    When set, the rendered destination bucket policy includes an extra statement granting roles from this
    permission set s3:ListBucket + s3:GetBucketLocation. AWS's current guidance doesn't require it; only
    use it if create-location-s3 for the destination bucket fails with AccessDenied.
  EOT
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention for the DataSync CloudWatch log group."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

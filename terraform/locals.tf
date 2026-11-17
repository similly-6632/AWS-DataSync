data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  destination_bucket_arn = "arn:${local.partition}:s3:::${var.destination_bucket_name}"

  # Any DataSync resource (location/task) in this account and region.
  datasync_source_arn_pattern = "arn:${local.partition}:datasync:${local.region}:${local.account_id}:*"

  bucket_level_actions = [
    "s3:GetBucketLocation",
    "s3:ListBucket",
    "s3:ListBucketMultipartUploads",
  ]

  source_object_actions = [
    "s3:GetObject",
    "s3:GetObjectTagging",
    "s3:GetObjectVersion",
    "s3:GetObjectVersionTagging",
    "s3:ListMultipartUploadParts",
  ]

  destination_object_actions = [
    "s3:AbortMultipartUpload",
    "s3:DeleteObject",
    "s3:GetObject",
    "s3:GetObjectTagging",
    "s3:GetObjectVersion",
    "s3:GetObjectVersionTagging",
    "s3:ListMultipartUploadParts",
    "s3:PutObject",
    "s3:PutObjectTagging",
  ]

  kms_actions = [
    "kms:Decrypt",
    "kms:Encrypt",
    "kms:GenerateDataKey",
    "kms:ReEncrypt*",
  ]
}

output "region" {
  description = "Region the DataSync locations and task must be created in."
  value       = local.region
}

output "name_prefix" {
  description = "Prefix used for naming; the CLI script uses it for the task name."
  value       = var.name_prefix
}

output "datasync_role_arn" {
  description = "IAM role DataSync assumes for both locations (BucketAccessRoleArn)."
  value       = aws_iam_role.datasync.arn
}

output "source_bucket_arn" {
  description = "ARN of the source bucket."
  value       = aws_s3_bucket.source.arn
}

output "destination_bucket_arn" {
  description = "ARN of the third party's destination bucket."
  value       = local.destination_bucket_arn
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for the DataSync task."
  value       = aws_cloudwatch_log_group.datasync.arn
}

output "location_creator_permission_set_name" {
  description = "Identity Center permission set expected to run the CLI script (empty if not set)."
  value       = var.location_creator_permission_set_name == null ? "" : var.location_creator_permission_set_name
}

output "destination_bucket_policy_json" {
  description = "Bucket policy to send to the third party for their destination bucket."
  value       = jsonencode(local.destination_bucket_policy)
}

output "destination_kms_key_policy_statement_json" {
  description = "KMS key policy statement to send to the third party if their bucket uses SSE-KMS."
  value       = jsonencode(local.destination_kms_key_policy_statement)
}

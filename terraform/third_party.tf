# Policies the third party must apply in THEIR account. Nothing here creates resources;
# the JSON is exposed via outputs so it can be sent to them.

locals {
  datasync_role_statement = {
    Sid       = "AllowSourceAccountDataSyncRole"
    Effect    = "Allow"
    Principal = { AWS = aws_iam_role.datasync.arn }
    Action    = concat(local.bucket_level_actions, local.destination_object_actions)
    Resource = [
      local.destination_bucket_arn,
      "${local.destination_bucket_arn}/*",
    ]
  }

  # Optional fallback for the identity running create-location-s3. Matches any role
  # provisioned from the Identity Center permission set, so it survives reprovisioning
  # (the AWSReservedSSO_<name>_<random> suffix changes).
  location_creator_statement = var.location_creator_permission_set_name == null ? [] : [{
    Sid       = "AllowSourceAccountLocationCreation"
    Effect    = "Allow"
    Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
    Action    = ["s3:GetBucketLocation", "s3:ListBucket"]
    Resource  = local.destination_bucket_arn
    Condition = {
      ArnLike = {
        "aws:PrincipalArn" = "arn:${local.partition}:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_${var.location_creator_permission_set_name}_*"
      }
    }
  }]

  destination_bucket_policy = {
    Version   = "2012-10-17"
    Statement = concat([local.datasync_role_statement], local.location_creator_statement)
  }

  # Statement to add to the destination KMS key policy, only needed if they use SSE-KMS.
  destination_kms_key_policy_statement = {
    Sid       = "AllowSourceAccountDataSyncRoleUseOfKey"
    Effect    = "Allow"
    Principal = { AWS = aws_iam_role.datasync.arn }
    Action    = local.kms_actions
    Resource  = "*"
  }
}

data "aws_iam_policy_document" "datasync_trust" {
  statement {
    sid     = "AllowDataSyncAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["datasync.amazonaws.com"]
    }

    # Confused-deputy protection: only DataSync resources in this account/region.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.datasync_source_arn_pattern]
    }
  }
}

resource "aws_iam_role" "datasync" {
  name                 = "${var.name_prefix}-role"
  description          = "Used by DataSync to read ${var.source_bucket_name} and write to ${var.destination_bucket_name} (${var.destination_account_id})."
  assume_role_policy   = data.aws_iam_policy_document.datasync_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "datasync_access" {
  statement {
    sid       = "SourceBucket"
    effect    = "Allow"
    actions   = local.bucket_level_actions
    resources = [aws_s3_bucket.source.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "SourceObjects"
    effect    = "Allow"
    actions   = local.source_object_actions
    resources = ["${aws_s3_bucket.source.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "DestinationBucket"
    effect    = "Allow"
    actions   = local.bucket_level_actions
    resources = [local.destination_bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.destination_account_id]
    }
  }

  statement {
    sid       = "DestinationObjects"
    effect    = "Allow"
    actions   = local.destination_object_actions
    resources = ["${local.destination_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [var.destination_account_id]
    }
  }

  dynamic "statement" {
    for_each = var.destination_kms_key_arn == null ? [] : [var.destination_kms_key_arn]

    content {
      sid       = "DestinationKmsKey"
      effect    = "Allow"
      actions   = local.kms_actions
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "datasync_access" {
  name   = "${var.name_prefix}-s3-access"
  role   = aws_iam_role.datasync.id
  policy = data.aws_iam_policy_document.datasync_access.json
}

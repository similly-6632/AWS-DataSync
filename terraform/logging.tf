resource "aws_cloudwatch_log_group" "datasync" {
  name              = "/aws/datasync/${var.name_prefix}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "datasync_logs" {
  statement {
    sid     = "DataSyncLogsToCloudWatchLogs"
    effect  = "Allow"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "${aws_cloudwatch_log_group.datasync.arn}:*",
    ]

    principals {
      type        = "Service"
      identifiers = ["datasync.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:datasync:${local.region}:${local.account_id}:task/*"]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "datasync" {
  policy_name     = "${var.name_prefix}-datasync-logs"
  policy_document = data.aws_iam_policy_document.datasync_logs.json
}

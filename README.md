# Cross-account S3 → S3 DataSync (source account)

This sets up a DataSync transfer from a bucket in our AWS account to a third party's bucket in their
account. The DataSync task runs in **our** account, using one IAM role that reads our bucket and
writes to theirs.

| Piece | Where | How |
| --- | --- | --- |
| Source bucket (versioned, SSE-S3, private, TLS-only) | Our account | Terraform |
| DataSync IAM role + inline S3 (and optional KMS) policy | Our account | Terraform |
| CloudWatch log group + resource policy for DataSync | Our account | Terraform |
| Bucket policy, ACLs disabled, optional KMS key policy | **Their** account | Third party, using JSON rendered by Terraform |
| Source location, destination location, task | Our account | AWS CLI script |

The locations and task are created by script rather than Terraform because they can only be created
once the third party has applied the bucket policy.

## Prerequisites

- Terraform >= 1.5 and AWS provider 6.x (currently locked to 6.73.0)
- AWS CLI v2, signed in with IAM Identity Center: `aws sso login --profile <profile>`
- Your Identity Center permission set needs, in our account:
  - Terraform: create/manage S3 buckets, IAM roles/policies, CloudWatch log groups and log
    resource policies
  - Script: `datasync:CreateLocationS3`, `datasync:CreateTask`, `datasync:Describe*`, `datasync:List*`,
    `datasync:StartTaskExecution`, `datasync:CancelTaskExecution`, `datasync:TagResource`,
    `iam:PassRole` on the DataSync role (`iam:PassedToService = datasync.amazonaws.com`), and
    `iam:CreateServiceLinkedRole` (needed the first time an Enhanced mode task is created).
    AWS's managed `AWSDataSyncFullAccess` policy covers most of this.

## Steps

### 1. Create our resources

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # then edit
terraform init
terraform plan
terraform apply
```

Configure a remote backend (S3 state) in `versions.tf` before applying for real.

### 2. Send the policy to the third party

```bash
terraform output -raw destination_bucket_policy_json
terraform output -raw destination_kms_key_policy_statement_json   # only if they use SSE-KMS
```

Fill these into [docs/third-party-handoff.md](docs/third-party-handoff.md) and send it. **Wait for
them to confirm** before step 3.

If they tell you the bucket uses SSE-KMS, set `destination_kms_key_arn` in `terraform.tfvars` and
re-apply. That adds the KMS permissions to our role.

### 3. Create the DataSync locations and task

PowerShell:

```powershell
./scripts/New-DataSyncTask.ps1 -AwsProfile <profile> -SourcePrefix / -DestinationPrefix /incoming
```

Bash:

```bash
./scripts/create-datasync-task.sh --profile <profile> --source-prefix / --destination-prefix /incoming
```

Both scripts read the ARNs from the Terraform outputs and run:

```bash
aws datasync create-location-s3 --s3-bucket-arn <source_bucket_arn> --subdirectory / \
  --s3-config BucketAccessRoleArn=<datasync_role_arn> --region <region>

aws datasync create-location-s3 --s3-bucket-arn <destination_bucket_arn> --subdirectory /incoming \
  --s3-storage-class STANDARD --s3-config BucketAccessRoleArn=<datasync_role_arn> --region <region>

aws datasync create-task --name <name_prefix>-task --task-mode ENHANCED \
  --source-location-arn <source-loc> --destination-location-arn <dest-loc> \
  --cloud-watch-log-group-arn <log_group_arn> \
  --options VerifyMode=ONLY_FILES_TRANSFERRED,OverwriteMode=ALWAYS,TransferMode=CHANGED,PreserveDeletedFiles=PRESERVE,ObjectTags=PRESERVE,LogLevel=TRANSFER \
  --region <region>
```

The scripts are **not idempotent**. Re-running them creates new locations and a new task, so delete
the old ones first (`aws datasync delete-task` / `delete-location`).

Task options used:

- `TransferMode=CHANGED`: re-runs copy only new or changed objects.
- `PreserveDeletedFiles=PRESERVE`: objects deleted from our bucket are **not** deleted from theirs.
  Change to `REMOVE` for a true mirror.
- `OverwriteMode=ALWAYS`: changed objects overwrite the destination copy.
- `VerifyMode=ONLY_FILES_TRANSFERRED`: the only verification Enhanced mode supports.
- `ObjectTags=PRESERVE`: copies object tags (the role has the tagging permissions).

### 4. Run and monitor

```bash
aws datasync start-task-execution --task-arn <task-arn> --region <region> --profile <profile>
aws datasync describe-task-execution --task-execution-arn <execution-arn> --region <region> --profile <profile>
```

Logs go to `/aws/datasync/<name_prefix>` in CloudWatch Logs. For a first test, upload one small
object, run the task, check that `Status` is `SUCCESS`, and ask the third party to confirm they can
read it and that their account owns it.

## Troubleshooting

- **`create-location-s3` for the destination returns AccessDenied.** Check the third party applied
  the bucket policy with our exact role ARN. If it still fails, set
  `location_creator_permission_set_name` in `terraform.tfvars`, re-apply and resend the bucket
  policy. That adds a temporary list-only statement for our Identity Center permission set. It
  matches `AWSReservedSSO_<PermissionSet>_*` rather than the exact role ARN, so it survives the
  permission set being reprovisioned.
- **Writes fail with KMS errors.** The bucket uses SSE-KMS. Set `destination_kms_key_arn`,
  re-apply, and have them add the key policy statement.
- **Third party can't read objects.** Their bucket still has ACLs enabled. Ask them to set Object
  Ownership to *Bucket owner enforced*.

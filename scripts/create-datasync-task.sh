#!/usr/bin/env bash
# Creates the DataSync source location, cross-account destination location and task.
# Bash equivalent of New-DataSyncTask.ps1. Reads ARNs from the Terraform outputs.
#
# Run only AFTER the third party confirms their bucket policy (and KMS key policy, if
# applicable) is in place. NOT idempotent: each run creates new locations and a new task.
#
# Usage:
#   aws sso login --profile my-sso-profile
#   ./scripts/create-datasync-task.sh --profile my-sso-profile --destination-prefix /incoming
#
# Options:
#   --profile NAME                 AWS CLI profile
#   --source-prefix PATH           default "/"
#   --destination-prefix PATH      default "/"
#   --task-mode ENHANCED|BASIC     default ENHANCED
#   --storage-class CLASS          destination storage class, default STANDARD
#   --task-name NAME               default "<name_prefix>-task"
#   --terraform-dir DIR            default "<script dir>/../terraform"
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

aws_profile=""
source_prefix="/"
destination_prefix="/"
task_mode="ENHANCED"
storage_class="STANDARD"
task_name=""
terraform_dir="${script_dir}/../terraform"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)            aws_profile="$2"; shift 2 ;;
    --source-prefix)      source_prefix="$2"; shift 2 ;;
    --destination-prefix) destination_prefix="$2"; shift 2 ;;
    --task-mode)          task_mode="$2"; shift 2 ;;
    --storage-class)      storage_class="$2"; shift 2 ;;
    --task-name)          task_name="$2"; shift 2 ;;
    --terraform-dir)      terraform_dir="$2"; shift 2 ;;
    -h|--help)            sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$task_mode" in ENHANCED|BASIC) ;; *) echo "--task-mode must be ENHANCED or BASIC" >&2; exit 2 ;; esac

tf_output() {
  terraform -chdir="$terraform_dir" output -raw "$1" || {
    echo "terraform output '$1' failed. Has 'terraform apply' been run in $terraform_dir?" >&2
    exit 1
  }
}

normalise_prefix() {
  local p="$1"
  [[ "$p" == /* ]] || p="/$p"
  printf '%s' "$p"
}

region="$(tf_output region)"
role_arn="$(tf_output datasync_role_arn)"
source_bucket_arn="$(tf_output source_bucket_arn)"
destination_bucket_arn="$(tf_output destination_bucket_arn)"
log_group_arn="$(tf_output log_group_arn)"
permission_set="$(tf_output location_creator_permission_set_name)"
[[ -n "$task_name" ]] || task_name="$(tf_output name_prefix)-task"

source_prefix="$(normalise_prefix "$source_prefix")"
destination_prefix="$(normalise_prefix "$destination_prefix")"

aws_cmd() {
  local common=(--region "$region" --output text)
  [[ -n "$aws_profile" ]] && common+=(--profile "$aws_profile")
  echo "> aws $*" >&2
  aws "$@" "${common[@]}"
}

# --- Identity check -------------------------------------------------------------------
caller_arn="$(aws_cmd sts get-caller-identity --query Arn)"
caller_account="$(cut -d: -f5 <<<"$caller_arn")"
role_account="$(cut -d: -f5 <<<"$role_arn")"
echo "Caller: $caller_arn"
if [[ "$caller_account" != "$role_account" ]]; then
  echo "Caller account $caller_account does not match the DataSync role's account $role_account. Check --profile." >&2
  exit 1
fi
if [[ -n "$permission_set" && "$caller_arn" != *":assumed-role/AWSReservedSSO_${permission_set}_"* ]]; then
  echo "WARNING: caller is not using permission set '$permission_set', which the destination bucket policy allows." >&2
fi

cat <<EOF

Region:        $region
Role:          $role_arn
Source:        $source_bucket_arn  ($source_prefix)
Destination:   $destination_bucket_arn  ($destination_prefix)
Task:          $task_name  [$task_mode]

EOF

# --- 1. Source location ---------------------------------------------------------------
source_location_arn="$(aws_cmd datasync create-location-s3 \
  --s3-bucket-arn "$source_bucket_arn" \
  --subdirectory "$source_prefix" \
  --s3-storage-class STANDARD \
  --s3-config "BucketAccessRoleArn=$role_arn" \
  --tags "Key=Name,Value=${task_name}-source" \
  --query LocationArn)"
echo "Source location:      $source_location_arn"

# --- 2. Destination location (cross-account) ------------------------------------------
destination_location_arn="$(aws_cmd datasync create-location-s3 \
  --s3-bucket-arn "$destination_bucket_arn" \
  --subdirectory "$destination_prefix" \
  --s3-storage-class "$storage_class" \
  --s3-config "BucketAccessRoleArn=$role_arn" \
  --tags "Key=Name,Value=${task_name}-destination" \
  --query LocationArn)"
echo "Destination location: $destination_location_arn"

# --- 3. Task --------------------------------------------------------------------------
options="VerifyMode=ONLY_FILES_TRANSFERRED,OverwriteMode=ALWAYS,TransferMode=CHANGED,PreserveDeletedFiles=PRESERVE,ObjectTags=PRESERVE,LogLevel=TRANSFER"

task_arn="$(aws_cmd datasync create-task \
  --name "$task_name" \
  --task-mode "$task_mode" \
  --source-location-arn "$source_location_arn" \
  --destination-location-arn "$destination_location_arn" \
  --cloud-watch-log-group-arn "$log_group_arn" \
  --options "$options" \
  --tags "Key=Name,Value=${task_name}" \
  --query TaskArn)"
echo "Task:                 $task_arn"

profile_arg=""
[[ -n "$aws_profile" ]] && profile_arg=" --profile $aws_profile"
cat <<EOF

Next steps (not run automatically):
  Start a transfer:
    aws datasync start-task-execution --task-arn $task_arn --region $region$profile_arg
  Check progress (use the TaskExecutionArn returned above):
    aws datasync describe-task-execution --task-execution-arn <TaskExecutionArn> --region $region$profile_arg
EOF

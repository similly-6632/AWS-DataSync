<#
.SYNOPSIS
    Creates the DataSync source location, cross-account destination location and task.

.DESCRIPTION
    Reads ARNs from the Terraform outputs in ../terraform, then runs the AWS CLI to:
      1. create the S3 source location (your bucket)
      2. create the S3 destination location (third party's bucket)
      3. create the DataSync task

    Run this only AFTER the third party confirms their bucket policy (and KMS key policy,
    if applicable) is in place. It is NOT idempotent: each run creates new locations and
    a new task.

.EXAMPLE
    aws sso login --profile my-sso-profile
    ./scripts/New-DataSyncTask.ps1 -AwsProfile my-sso-profile -DestinationPrefix /incoming
#>
[CmdletBinding()]
param(
    # AWS CLI named profile (e.g. your IAM Identity Center profile).
    [Alias('Profile')]
    [string]$AwsProfile,

    # Prefix (folder) to read from in the source bucket. "/" means the whole bucket.
    [string]$SourcePrefix = '/',

    # Prefix (folder) to write to in the destination bucket. "/" means the bucket root.
    [string]$DestinationPrefix = '/',

    [ValidateSet('ENHANCED', 'BASIC')]
    [string]$TaskMode = 'ENHANCED',

    [ValidateSet('STANDARD', 'INTELLIGENT_TIERING', 'STANDARD_IA', 'ONEZONE_IA', 'GLACIER_INSTANT_RETRIEVAL')]
    [string]$DestinationStorageClass = 'STANDARD',

    [string]$TaskName,

    [string]$TerraformDir = (Join-Path $PSScriptRoot '..\terraform')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TfOutput([string]$Name) {
    $value = & terraform "-chdir=$TerraformDir" output -raw $Name
    if ($LASTEXITCODE -ne 0) { throw "terraform output '$Name' failed. Has 'terraform apply' been run in $TerraformDir?" }
    return ($value | Out-String).Trim()
}

function Invoke-Aws {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $common = @('--region', $script:Region, '--output', 'text')
    if ($AwsProfile) { $common += @('--profile', $AwsProfile) }
    Write-Host "> aws $($Arguments -join ' ')" -ForegroundColor DarkGray
    $out = & aws @Arguments @common
    if ($LASTEXITCODE -ne 0) { throw "AWS CLI command failed (exit $LASTEXITCODE): aws $($Arguments -join ' ')" }
    return ($out | Out-String).Trim()
}

function ConvertTo-Subdirectory([string]$Prefix) {
    $p = $Prefix.Trim()
    if (-not $p.StartsWith('/')) { $p = "/$p" }
    return $p
}

# --- Inputs from Terraform -------------------------------------------------------------
$script:Region       = Get-TfOutput 'region'
$roleArn             = Get-TfOutput 'datasync_role_arn'
$sourceBucketArn     = Get-TfOutput 'source_bucket_arn'
$destinationBucketArn = Get-TfOutput 'destination_bucket_arn'
$logGroupArn         = Get-TfOutput 'log_group_arn'
$permissionSet       = Get-TfOutput 'location_creator_permission_set_name'
if (-not $TaskName) { $TaskName = "$(Get-TfOutput 'name_prefix')-task" }

$SourcePrefix      = ConvertTo-Subdirectory $SourcePrefix
$DestinationPrefix = ConvertTo-Subdirectory $DestinationPrefix

# --- Identity check --------------------------------------------------------------------
$callerArn = Invoke-Aws @('sts', 'get-caller-identity', '--query', 'Arn')
$callerAccount = ($callerArn -split ':')[4]
$roleAccount = ($roleArn -split ':')[4]
Write-Host "Caller: $callerArn"
if ($callerAccount -ne $roleAccount) {
    throw "Caller account $callerAccount does not match the DataSync role's account $roleAccount. Check -AwsProfile."
}
if ($permissionSet -and ($callerArn -notlike "*:assumed-role/AWSReservedSSO_$($permissionSet)_*")) {
    Write-Warning "Caller is not using permission set '$permissionSet', which the destination bucket policy allows. create-location-s3 for the destination may fail."
}

Write-Host ""
Write-Host "Region:        $script:Region"
Write-Host "Role:          $roleArn"
Write-Host "Source:        $sourceBucketArn  ($SourcePrefix)"
Write-Host "Destination:   $destinationBucketArn  ($DestinationPrefix)"
Write-Host "Task:          $TaskName  [$TaskMode]"
Write-Host ""

# --- 1. Source location ----------------------------------------------------------------
$sourceLocationArn = Invoke-Aws @(
    'datasync', 'create-location-s3',
    '--s3-bucket-arn', $sourceBucketArn,
    '--subdirectory', $SourcePrefix,
    '--s3-storage-class', 'STANDARD',
    '--s3-config', "BucketAccessRoleArn=$roleArn",
    '--tags', "Key=Name,Value=$TaskName-source",
    '--query', 'LocationArn'
)
Write-Host "Source location:      $sourceLocationArn" -ForegroundColor Green

# --- 2. Destination location (cross-account) -------------------------------------------
$destinationLocationArn = Invoke-Aws @(
    'datasync', 'create-location-s3',
    '--s3-bucket-arn', $destinationBucketArn,
    '--subdirectory', $DestinationPrefix,
    '--s3-storage-class', $DestinationStorageClass,
    '--s3-config', "BucketAccessRoleArn=$roleArn",
    '--tags', "Key=Name,Value=$TaskName-destination",
    '--query', 'LocationArn'
)
Write-Host "Destination location: $destinationLocationArn" -ForegroundColor Green

# --- 3. Task ---------------------------------------------------------------------------
$options = @(
    'VerifyMode=ONLY_FILES_TRANSFERRED',
    'OverwriteMode=ALWAYS',
    'TransferMode=CHANGED',
    'PreserveDeletedFiles=PRESERVE',
    'ObjectTags=PRESERVE',
    'LogLevel=TRANSFER'
) -join ','

$taskArn = Invoke-Aws @(
    'datasync', 'create-task',
    '--name', $TaskName,
    '--task-mode', $TaskMode,
    '--source-location-arn', $sourceLocationArn,
    '--destination-location-arn', $destinationLocationArn,
    '--cloud-watch-log-group-arn', $logGroupArn,
    '--options', $options,
    '--tags', "Key=Name,Value=$TaskName",
    '--query', 'TaskArn'
)
Write-Host "Task:                 $taskArn" -ForegroundColor Green

# --- Next steps ------------------------------------------------------------------------
$profileArg = if ($AwsProfile) { " --profile $AwsProfile" } else { '' }
Write-Host ""
Write-Host "Next steps (not run automatically):"
Write-Host "  Start a transfer:"
Write-Host "    aws datasync start-task-execution --task-arn $taskArn --region $script:Region$profileArg"
Write-Host "  Check progress (use the TaskExecutionArn returned above):"
Write-Host "    aws datasync describe-task-execution --task-execution-arn <TaskExecutionArn> --region $script:Region$profileArg"

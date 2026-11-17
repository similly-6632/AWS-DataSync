# Third-party handoff: destination bucket setup

Send this to the owner of the destination bucket. Everything here happens in **their** AWS account.
Paste the JSON from the Terraform outputs into the placeholders before sending:

```bash
terraform -chdir=terraform output -raw destination_bucket_policy_json
terraform -chdir=terraform output -raw destination_kms_key_policy_statement_json
```

---

We will copy data into your S3 bucket `<destination-bucket>` with AWS DataSync, running in our AWS
account `<source-account-id>`. All writes come from one IAM role in our account:
`<datasync_role_arn>`.

Before we can start, please:

1. **Add our statement(s) to your bucket policy.** Merge them into any existing policy rather than
   replacing it:

   ```json
   <destination_bucket_policy_json>
   ```

   - If there is a statement with Sid `AllowSourceAccountLocationCreation`, it is only needed while we
     set up the transfer. You can remove it once we confirm the DataSync location exists.

2. **Disable ACLs on the bucket.** Set *Permissions → Object Ownership* to **ACLs disabled
   (Bucket owner enforced)**. This makes your account own every object we write. If ACLs stay
   enabled, the objects stay owned by our account and you may not be able to read them.

3. **If the bucket uses SSE-KMS with a customer managed key**, add this statement to the key policy
   and send us the key ARN:

   ```json
   <destination_kms_key_policy_statement_json>
   ```

   No change is needed for SSE-S3 (the default encryption).

4. **Confirm with us:**
   - the bucket's region (we're assuming `<region>`)
   - the prefix/folder we should write into, if it isn't the bucket root
   - whether any SCPs, VPC endpoint policies or bucket policy `Deny` statements (for example requiring
     a specific encryption header) could block writes from an external account

Our role only gets list, read, write, delete and tagging permissions on this bucket, and only the
actions DataSync needs. `s3:DeleteObject` is needed for multipart cleanup and overwrites. Our task
is set to **keep** objects in your bucket even after they're deleted from ours.

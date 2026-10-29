# Lab 7: from CloudFormation to Terraform

Spry · student: Yuliana Ivanchenko · 2026-10-29

## Submission

| # | Item | Where |
|---|---|---|
| 1 | Commit that replaces the three CloudFormation templates with Terraform in `infra/`, updates the Makefile and the README, and adds ADR 0007 | **[13a2280](https://github.com/Yuna-Iv/spry/commit/13a228073ddd8699f6bc53d0141d329ffc507635)** · https://github.com/Yuna-Iv/spry/commit/13a228073ddd8699f6bc53d0141d329ffc507635 |
| 2 | HCP Terraform run of workspace `spry-dev` that finished with **Apply finished**, started by a merge (pull request #1), not from a laptop | [below](#2-apply-finished-started-by-a-merge) |
| 3 | `terraform plan` right after the migration: **No changes. Your infrastructure matches the configuration.** | [below](#3-terraform-plan-after-the-migration) |

## What was done

**Layout.** `infra/versions.tf` (HCP Terraform `cloud` block: organization `ooad-yuna-iv`, workspace
`spry-dev`; AWS provider 6.x with `default_tags` for `PROJECT_NAME`), `variables.tf`, `data.tf`,
`auth.tf` (was `auth.yaml`, Lab 4), `reports.tf` (was `reports.yaml`, Lab 5), `ai.tf` (was `ai.yml`,
Lab 6), `outputs.tf`, `terraform.tfvars` (non-secret values only), `mailer/index.py` (the mailer's
code, inline in the old template). The older stacks (ECR, backend and database, frontend, GitHub
OIDC) stay on CloudFormation; `data.tf` reads the backend function (image, network, database URL)
and the frontend stack's addresses.

**Credentials and secrets.** The workspace runs remotely with dynamic credentials
(`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`): every run exchanges an OIDC token for the role
`hcp-terraform-ooad-yuna-iv`, created by a separate bootstrap configuration with local state. The
role trusts only workspace `spry-dev`, not every workspace of the organization. The Google client
secret is a sensitive workspace variable; the report and budget email addresses are workspace
variables too.

**Migration without losing anything** (2 user accounts in the pool, 3 reports in the bucket):

1. `terraform plan` with 26 `import` blocks, while the stacks still existed, until the plan showed
   only imports, the four new roles and their in-place use (fixed on the way: the standard
   attribute `name` in the pool's schema, the SQS default message size, the
   `invoked_via_function_url` condition of the parser's permission).
2. `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain` on all 27 resources of the three
   stacks (a script added them to the repository's templates and updated the stacks with
   `UsePreviousValue` for every parameter), checked in the deployed templates, then the stacks were
   deleted. The pool still had 2 users and the bucket 3 reports.
3. `terraform apply`: **26 imported, 11 added, 5 changed, 0 destroyed.**

**Re-created instead of imported:** the four IAM roles (with their inline policies and managed
policy attachments): `spry-report-builder`, `spry-report-scheduler`, `spry-report-mailer`,
`spry-agenda-parser`. CloudFormation had named them `spry-reports-BuilderRole-O6egmys8cREr` and so
on; keeping those names in the code would have been noise. A role holds no data, and the three
functions and the schedule switched to the new roles in place (the 5 changes above), so nothing was
interrupted. The old roles were deleted by hand. Everything else, including the three Lambda
permission statements, was imported; the user pool and the reports bucket have `prevent_destroy`.

**Makefile and pipeline.** The scripts read `terraform -chdir=infra output -raw …` instead of stack
outputs. `make infra-init`, `infra-plan`, `infra-output`, `infra-env` (writes the Cognito ids to
`.env`); `deploy-auth`, `deploy-reports`, `deploy-ai` and their `destroy-*` are gone, and there is no
`apply` in the Makefile. The workspace is connected to the repository (working directory `infra`,
runs only for changes under `infra/`, auto-apply): a pull request gets a plan as a check, a merge
is applied. GitHub Actions still deploys the application (`make deploy`) and reads the Terraform
outputs with a token (`TF_API_TOKEN`); it also moves the report builder and the parser to each new
backend image, which Terraform ignores (`image_uri` in `ignore_changes`).

## 2. Apply finished, started by a merge

[Pull request #1](https://github.com/Yuna-Iv/spry/pull/1) (`infra/parser-log-retention`) changed `retention_in_days` of the parser's log group
from 14 to 30. The PR got a speculative plan as a check (`1 to change`); the merge started this run.
"Yuna-Iv triggered a run from GitHub", Plan finished (`0 to add, 1 to change, 0 to destroy`),
**Apply finished** (`0 added, 1 changed, 0 destroyed`):

![HCP Terraform run of spry-dev: Merge pull request #1, triggered from GitHub, Apply finished, 1 changed](docs/images/lab7-apply-finished.png)

## 3. `terraform plan` after the migration

Run from `infra/` right after the apply (the plan runs in HCP Terraform):

```
Running plan in HCP Terraform. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the plan running remotely.

Preparing the remote plan...

To view this run in a browser, visit:
https://app.terraform.io/app/ooad-yuna-iv/spry-dev/runs/run-dkFbaAxXBbkHq7ch

Waiting for the plan to start...

Terraform v1.17.1
on linux_amd64

Initializing plugins and modules...
data.archive_file.mailer: Refreshing...
data.archive_file.mailer: Refresh complete after 0s [id=731566fae142bbeac5d60538e331a83647845567]
data.aws_lambda_function.backend: Refreshing...
aws_cloudwatch_log_group.parser: Refreshing state... [id=/spry/agenda-parser]
aws_cloudwatch_log_group.builder: Refreshing state... [id=/spry/report-builder]
aws_sesv2_email_identity.sender: Refreshing state... [id=iyunanext@gmail.com]
aws_cloudwatch_log_group.mailer: Refreshing state... [id=/spry/report-mailer]
aws_budgets_budget.monthly[0]: Refreshing state... [id=576889497513:spry-monthly]
aws_cognito_user_pool.main: Refreshing state... [id=eu-central-1_wLilvi79o]
data.aws_caller_identity.current: Refreshing...
data.aws_cloudformation_stack.frontend: Refreshing...
aws_sqs_queue.requests_dlq: Refreshing state... [id=https://sqs.eu-central-1.amazonaws.com/576889497513/spry-report-requests-dlq]
data.aws_caller_identity.current: Refresh complete after 0s [id=576889497513]
aws_iam_role.parser: Refreshing state... [id=spry-agenda-parser]
aws_iam_role.builder: Refreshing state... [id=spry-report-builder]
aws_iam_role.mailer: Refreshing state... [id=spry-report-mailer]
aws_iam_role_policy.parser: Refreshing state... [id=spry-agenda-parser:call-bedrock]
aws_iam_role_policy_attachment.parser_logs: Refreshing state... [id=spry-agenda-parser/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_iam_role_policy_attachment.builder_vpc: Refreshing state... [id=spry-report-builder/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole]
aws_iam_role_policy_attachment.mailer_logs: Refreshing state... [id=spry-report-mailer/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_iam_role.scheduler: Refreshing state... [id=spry-report-scheduler]
aws_s3_bucket.reports: Refreshing state... [id=spry-reports-576889497513]
aws_lambda_function.mailer: Refreshing state... [id=spry-report-mailer]
aws_sqs_queue.requests: Refreshing state... [id=https://sqs.eu-central-1.amazonaws.com/576889497513/spry-report-requests]
data.aws_cloudformation_stack.frontend: Refresh complete after 0s [id=arn:aws:cloudformation:eu-central-1:576889497513:stack/spry-frontend/786e02d0-c358-11f1-b002-02ffd090c3cf]
data.aws_lambda_function.backend: Refresh complete after 0s [id=spry-backend]
data.aws_route_table.main: Refreshing...
aws_iam_role_policy.scheduler: Refreshing state... [id=spry-report-scheduler:send-report-requests]
aws_scheduler_schedule.weekly: Refreshing state... [id=default/spry-weekly-report]
aws_cognito_user_pool_domain.main: Refreshing state... [id=spry-576889497513]
aws_cognito_identity_provider.google[0]: Refreshing state... [id=eu-central-1_wLilvi79o:Google]
aws_cognito_user_pool_client.web: Refreshing state... [id=3untppls7np2f5mdvt6cjs9hrl]
data.aws_route_table.main: Refresh complete after 1s [id=rtb-0b10dea992272dee1]
aws_vpc_endpoint.s3: Refreshing state... [id=vpce-05c576972282ee648]
aws_cognito_managed_login_branding.web: Refreshing state...
aws_lambda_function.parser: Refreshing state... [id=spry-agenda-parser]
aws_lambda_permission.parser_url: Refreshing state... [id=spry-ai-FunctionUrlPermission-YwDBNNnjPU6m]
aws_lambda_function_url.parser: Refreshing state... [id=spry-agenda-parser]
aws_lambda_permission.parser_invoke: Refreshing state... [id=spry-ai-FunctionInvokePermission-PVOtdDmngixj]
aws_iam_role_policy.mailer: Refreshing state... [id=spry-report-mailer:mail-reports]
aws_iam_role_policy.builder: Refreshing state... [id=spry-report-builder:build-reports]
aws_lambda_permission.mailer_s3: Refreshing state... [id=spry-reports-MailerS3Permission-EhVoiJ8wC8E6]
aws_s3_bucket_public_access_block.reports: Refreshing state... [id=spry-reports-576889497513]
aws_s3_bucket_lifecycle_configuration.reports: Refreshing state... [id=spry-reports-576889497513]
aws_lambda_function.builder: Refreshing state... [id=spry-report-builder]
aws_s3_bucket_notification.reports: Refreshing state... [id=spry-reports-576889497513]
aws_lambda_event_source_mapping.builder: Refreshing state... [id=a4fd4181-b493-4e90-ba7b-337582703215]
aws_iam_role.mailer: Drift detected (update)
aws_iam_role.scheduler: Drift detected (update)
aws_iam_role.builder: Drift detected (update)
aws_iam_role.parser: Drift detected (update)

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```

The four `Drift detected (update)` lines are informational: AWS updates a role's "last used"
information when a function uses it, outside of Terraform. Terraform records it in the state and
finds no difference between the configuration and AWS, hence **No changes**.

## Step 5: drift

The parser's timeout was changed by hand in the Lambda console from 30 to 45 seconds. A run started
in HCP Terraform found it (`timeout: 45 → 30`, `1 to change`) and put it back:

![HCP Terraform run started from the UI: aws_lambda_function.parser, timeout 45 → 30](docs/images/lab7-drift-plan.png)

If that had been a real fix at 23:00, the next apply would have undone it. The fix has to land in
the code: the same change in `infra/ai.tf` as a pull request, merged before the next apply, so the
plan shows `No changes` and the fix is reviewed and kept. Better still, make the fix through a pull
request in the first place: plan and apply take a few minutes.

Decision record: [ADR 0007 — Terraform for the infrastructure added in Labs 4–6](adr/0007-terraform.md).

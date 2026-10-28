# ADR 0007: Terraform for the infrastructure added in Labs 4–6

- Status: accepted
- Date: 2026-10-28

## Context

Labs 4–6 added three CloudFormation templates: `infra/auth.yaml` (Cognito), `infra/reports.yaml`
(the weekly report) and `infra/ai.yml` (the agenda parser). They were deployed by `make deploy-*`
scripts from a laptop or from GitHub Actions, with the parameters (the Google client secret, the
report email, the model) coming from `.env` or GitHub variables.

That worked, but:

- **The project already reaches outside AWS**: the Google OAuth client, the GitHub repository and
  its OIDC trust, and HCP Terraform itself. CloudFormation stops at the edge of one AWS account.
- **A second environment is coming** (stage, or a white-label copy). With CloudFormation each
  one is a set of stacks plus the right `.env`; there is no single place that says what an
  environment is.
- **Changes were not reviewed as infrastructure.** A template change reached AWS when someone ran
  `make deploy`, and a change set was optional. Nobody saw "this destroys the user pool" before it
  happened; only `DeletionPolicy: Retain` on the pool protected the accounts.
- **The resources hold data**: 2 user accounts in the pool, 3 reports in the bucket. The migration
  must not lose them.

## Decision

1. **Terraform** (AWS provider 6.x) describes the three parts in `infra/auth.tf`, `infra/reports.tf`
   and `infra/ai.tf`, one root module with `variables.tf`, `data.tf`, `outputs.tf` and
   `terraform.tfvars`. The older stacks (ECR, backend and database, frontend, GitHub OIDC) stay on
   CloudFormation for now; `data.tf` reads what Terraform needs from them (the backend function's
   image, network and database URL, the frontend stack's addresses).
2. **The state lives in HCP Terraform**, workspace `spry-dev` in organization `ooad-yuna-iv`,
   remote execution. It is locked during every run and every version of it is kept.
3. **HCP Terraform is the only road to apply.** The workspace is connected to the GitHub
   repository (working directory `infra`): every pull request gets a speculative plan as a check,
   every merge to `main` is planned and applied. The Makefile has `infra-plan`, `infra-output` and
   `infra-env`, and no `apply`.
4. **No AWS keys in HCP Terraform.** Runs use dynamic credentials: HCP Terraform signs an OIDC token
   per run, AWS exchanges it for temporary credentials of the role `hcp-terraform-ooad-yuna-iv`.
   The role trusts only the workspace `spry-dev` of this organization. It is created by a small
   bootstrap configuration with local state, outside this repository, because it has to exist
   before HCP Terraform can do anything.
5. **Two roads, one direction.** GitHub Actions still deploys the application (`make deploy`: the
   backend image and stack, the frontend) and reads the Terraform outputs it needs (Cognito ids,
   the parser URL) with a read token. The report builder and the parser run the backend image;
   Terraform creates them and ignores `image_uri`, and `make deploy-backend` moves them to each new
   image. When a change needs both roads (a new environment variable for a function), the
   infrastructure change is merged and applied first, then the application that uses it.
6. **The migration adopted the resources instead of re-creating them**: every resource got
   `DeletionPolicy: Retain`, the stacks were deleted, and `import` blocks handed the 26 resources to
   Terraform until `terraform plan` showed only imports. The user pool and the reports bucket have
   `prevent_destroy`.

## Alternatives considered

- **Keep CloudFormation.** AWS keeps the state and rolls back failed changes, and new AWS services
  arrive there first. It lost because it covers one AWS account only, change sets are optional, and
  every environment would be another set of stacks with parameters in `.env` files.
- **AWS CDK.** Real code (TypeScript or Python) on top of CloudFormation: loops, types, tests.
  It still deploys CloudFormation, so the same one-account limit, plus a build step and a
  bootstrap stack, for a project whose infrastructure is a few dozen resources.
- **OpenTofu.** The open-source fork accepts the same files and commands, under the MPL licence
  instead of Terraform's BSL. It lost only on the course setup: HCP Terraform, its free tier and
  its dynamic credentials are what the course uses. The code would move to OpenTofu unchanged.
- **Applying from laptops with remote state** (or from GitHub Actions). Possible, but then AWS
  admin credentials sit on laptops or in CI for infrastructure changes. With HCP Terraform runs,
  nobody needs AWS keys to change the infrastructure, and every apply has a plan and a commit.

## Consequences

- **Who can change the infrastructure:** anyone who can merge to `main`, through a pull request
  whose plan they read. Applying from a laptop is not possible on a VCS-connected workspace; an
  emergency fix goes through the same road, or through the console followed by a pull request
  that writes the fix into `infra/*.tf` (otherwise the next apply undoes it).
- **Where the secrets end up:** the Google client secret is a sensitive variable of the HCP
  Terraform workspace (write-only in the UI, `(sensitive value)` in plans). It is also in the
  **state** in plain text, together with the database URL that the report builder gets from the
  backend function. The state is stored and encrypted in HCP Terraform; anyone with read access to
  the workspace's state can read them. The CI token can read outputs and state too, so it is a
  repository secret, not a variable.
- **If HCP Terraform is down:** the application keeps working; nothing in Spry calls HCP Terraform
  at run time. Infrastructure changes wait. `make deploy` in CI fails at reading the outputs (the
  Cognito ids and the parser URL could be passed by hand in an emergency). A laptop could plan
  against a copy of the state, but must not apply around the lock.
- **What was re-created:** the four IAM roles of the functions and the schedule (CloudFormation had
  given them generated names such as `spry-reports-BuilderRole-O6egmys8cREr`). A role holds no
  data and every function switched to its new role in place; the old roles were deleted by hand.
  Everything else, including the Lambda permission statements, was imported.
- **New costs and duties:** the state is ours to protect (in HCP Terraform, not in Git), the free
  tier limits the number of managed resources, and provider upgrades are pinned in
  `.terraform.lock.hcl` and reviewed like any other dependency.
- **Drift is visible:** every plan compares the code with AWS, and a change made in the console
  shows up in the next plan as something Terraform will put back.

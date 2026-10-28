# Meetings App

List, create, and delete meetings with participants. FastAPI + PostgreSQL backend, React + shadcn/ui frontend, all run with Docker Compose. See [SPEC.md](SPEC.md) for the full specification.

## Quick start

Requires Docker.

```sh
make up      # creates .env from .env.example, builds and starts everything
make seed    # optional: sample participants and meetings
```

- App: http://localhost:3000
- API docs: http://localhost:8000/api/docs

If port 5432 is already in use on your machine, set `DB_PORT` in `.env` (e.g. `DB_PORT=5433`).

## Common commands

Run `make` to list all targets. The most used:

| Command | What it does |
|---|---|
| `make up` / `make down` | Start / stop the stack |
| `make logs s=backend` | Follow logs of one service |
| `make test` | Backend tests (in the backend container, against `<db>_test`) |
| `make lint` / `make format` | Ruff + oxlint/Prettier |
| `make migration m="..."` | Autogenerate an Alembic migration |
| `make psql` | Open a psql shell |
| `make clean` | Stop and delete the database volume |

## Local development without rebuilding images

Requires [uv](https://docs.astral.sh/uv/) and Node.js.

```sh
make install        # uv sync + npm install
make dev-backend    # Postgres in Docker, API on :8000 with reload
make dev-frontend   # Vite on :5173, proxies /api to :8000
```

## Deploy to AWS

Everything is described as code in [`infra/`](infra/), in two tools and on two roads:

| What | Tool | Who deploys it |
|---|---|---|
| Cognito ([`auth.tf`](infra/auth.tf)), the weekly report ([`reports.tf`](infra/reports.tf)), the agenda parser and the $5 budget ([`ai.tf`](infra/ai.tf)) | **Terraform**, state in HCP Terraform (workspace `spry-dev`) | **HCP Terraform**: a plan on every pull request, an apply on every merge to `main`. Nobody applies from a laptop. |
| ECR, the backend Lambda and its database, the frontend (S3 + CloudFront), the GitHub OIDC role | CloudFormation (`infra/*.yaml`) | `make deploy`, locally or from GitHub Actions on every push to `main` |
| The application code (backend image, frontend build) | Docker, Vite | `make deploy`; it also moves the report builder and the agenda parser to the new backend image |

Terraform reads what it needs from the CloudFormation stacks (`data.tf`: the backend function's image, network and database URL, the frontend's addresses), and the deploy scripts read the Terraform outputs (`terraform -chdir=infra output`). The region is `AWS_REGION` in `.env` (and `region` in [`infra/terraform.tfvars`](infra/terraform.tfvars)).

### The Terraform part

- **Settings** that are not secret are in [`infra/terraform.tfvars`](infra/terraform.tfvars) and go through review like code. Secrets (`google_client_secret`) and personal values (`report_email`, `budget_email`) are variables of the HCP Terraform workspace; `google_client_secret` is marked sensitive there.
- **Credentials:** HCP Terraform runs get short-lived AWS credentials through OIDC (dynamic credentials: `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` on the workspace). The role is created once, outside this repository, with a small bootstrap configuration with local state.
- **Changing it:** edit `infra/*.tf`, open a pull request, read the plan in the HCP Terraform check, merge. HCP Terraform applies. `make infra-plan` shows the same plan from your laptop (it runs in HCP Terraform and changes nothing).
- **On your laptop:** install Terraform 1.10+, run `terraform login` once, then `make infra-init`. `make infra-output` prints the outputs; `make infra-env` writes the Cognito settings to `.env` for local runs.
- **CI** needs a repository secret `TF_API_TOKEN` (an HCP Terraform team token) so that `make deploy` can read the outputs.
- **Drift:** a change made by hand in the console shows up in the next plan, and the next apply puts it back. Fix things in `infra/*.tf`, not in the console.

### The CloudFormation part


- **Backend** (`make deploy-backend`): the backend container on AWS Lambda (via [Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter), so the FastAPI app runs unchanged), exposed through a public **Lambda function URL**, and its PostgreSQL 17 database on **Aurora Serverless v2 scaling between 0 and 1 ACU**. After 5 idle minutes the database pauses and costs only storage; the first request after that waits about 15 seconds while it resumes. The function runs in the database's private subnets; there is no NAT gateway, load balancer or public IP.
- **Frontend** (`make deploy-frontend`): the app, built with `VITE_API_URL` set to the function URL, in a private S3 bucket behind CloudFront on **pay-as-you-go** pricing (no flat-rate plan; `PriceClass_100`). The browser calls the function URL directly; the deploy adds the CloudFront address to the backend's CORS origins.

1. Put the credentials of an IAM user into `.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`; see `.env.example` for the optional settings). `.env` is gitignored.
2. `make deploy` (backend, then frontend). It prints the app and API URLs. The first run takes about 20 minutes (database and CloudFront distribution); later runs take a few minutes. Deploy the two parts separately with `make deploy-backend` / `make deploy-frontend`.
3. `make destroy-frontend` and `make destroy-backend` delete those stacks, except a final database snapshot. The Terraform part is destroyed from HCP Terraform (Settings → Destruction and Deletion); the user pool and the reports bucket refuse it (`prevent_destroy`) until that line is removed on purpose.

On a new AWS account the order is: the backend (`make deploy-backend`, it needs the Cognito ids, so the very first time apply the Terraform workspace first with an empty frontend), the Terraform part (HCP Terraform), then the frontend (`make deploy-frontend`).

Requires Docker, Node.js, the AWS CLI and Terraform. `make infra-lint` checks the CloudFormation templates and the Terraform files.

### Custom domain

Once everything is deployed, set the domain in `.env` and attach it:

```sh
DOMAIN_NAME=app.example.com
HOSTED_ZONE_ID=Z0123456789ABC   # optional: only if the domain's DNS is in Route 53
```

```sh
make add-domain
```

This requests an ACM certificate in `us-east-1` (the only region CloudFront accepts), adds the domain to the CloudFront distribution and to the backend's CORS origins. Cognito's redirect URLs and the parser's CORS origins are Terraform resources: the next HCP Terraform run picks up the new domain from the frontend stack. With `HOSTED_ZONE_ID`, the validation and alias records are created in Route 53 for you. Without it, the command prints the validation CNAME to add at your DNS provider, waits for the certificate, and then prints the CNAME that points the domain at CloudFront. Later `make deploy` runs keep the domain. `make remove-domain` detaches it again (to switch domains: `make remove-domain`, change `DOMAIN_NAME`, `make add-domain`).

### Tags

Every AWS resource that supports tags is tagged `PROJECT_NAME=<PROJECT_NAME>` (in the CloudFormation templates as `Key: PROJECT_NAME, Value: !Ref ProjectName` plus stack tags, in Terraform once through `default_tags` in [`infra/versions.tf`](infra/versions.tf), and on the SSM parameter). Find the whole app with Resource Groups & Tag Editor, and split out its costs in Billing once `PROJECT_NAME` is activated as a cost allocation tag. `APP_NAME` in older `.env` files still works as the project name.

## Layout

```
backend/    FastAPI app (app/), Alembic migrations (alembic/), tests (tests/)
frontend/   Vite + React + shadcn/ui (src/components/ui is generated by shadcn)
infra/      Terraform (*.tf, state in HCP Terraform), CloudFormation templates (*.yaml) and deploy scripts
```

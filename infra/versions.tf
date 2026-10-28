# Terraform for the parts of Spry that Labs 4-6 built with CloudFormation: Cognito (auth.tf),
# the weekly report (reports.tf) and the agenda parser (ai.tf). The state lives in HCP Terraform,
# workspace spry-dev, which plans every pull request and applies every merge to main.
#
# The older stacks (ECR, backend + database, frontend, GitHub OIDC) stay on CloudFormation;
# data.tf reads what this configuration needs from them.

terraform {
  required_version = ">= 1.10"

  cloud {
    organization = "ooad-yuna-iv"

    workspaces {
      name = "spry-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

# Credentials: in HCP Terraform, dynamic credentials (TFC_AWS_PROVIDER_AUTH and
# TFC_AWS_RUN_ROLE_ARN on the workspace) give every run a short-lived role. Never a key here.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      PROJECT_NAME = var.project_name
    }
  }
}

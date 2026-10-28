# What this configuration reads from the rest of the system. The backend, its database and the
# frontend are still CloudFormation stacks (infra/backend.yaml, infra/frontend.yaml).

data "aws_caller_identity" "current" {}

# The API function: its image, its database URL and its network, which the report builder
# shares (same subnets and security group, so the database lets it in).
data "aws_lambda_function" "backend" {
  function_name = "${var.project_name}-backend"
}

# The frontend's addresses: Cognito redirects back to them, and the parser lets them call it.
data "aws_cloudformation_stack" "frontend" {
  name = "${var.project_name}-frontend"
}

# The backend's subnets have no route table of their own, so they use the VPC's main one.
data "aws_route_table" "main" {
  vpc_id = local.vpc_id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  backend_env        = data.aws_lambda_function.backend.environment[0].variables
  vpc_id             = data.aws_lambda_function.backend.vpc_config[0].vpc_id
  subnet_ids         = data.aws_lambda_function.backend.vpc_config[0].subnet_ids
  security_group_ids = data.aws_lambda_function.backend.vpc_config[0].security_group_ids

  # The image the functions start from. After that the app pipeline (make deploy-backend)
  # moves them to each new image, so Terraform ignores image_uri changes (see the functions).
  image_uri = data.aws_lambda_function.backend.image_uri

  frontend_urls = compact([
    for key in ["AppUrl", "CustomDomainUrl"] :
    trimsuffix(try(data.aws_cloudformation_stack.frontend.outputs[key], ""), "/")
  ])
  # Local dev servers too: signing in with Google on localhost needs the same redirect.
  app_urls     = concat(["http://localhost:5173", "http://localhost:3000"], local.frontend_urls)
  cors_origins = concat(local.frontend_urls, var.extra_cors_origins)

  reports_bucket = "${var.project_name}-reports-${local.account_id}"
}

# The agenda parser (was infra/ai.yml, Lab 6). A Lambda function with a public, authenticated
# function URL: the browser sends pasted text, the function asks Claude on Amazon Bedrock for a
# structured agenda, validates it and returns JSON. Outside the VPC (it never touches the
# database), so it reaches Bedrock over the internet: no NAT, no VPC endpoint. Saving goes through
# the main API, never through this function. Also the $5 monthly budget alarm.

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/${var.project_name}/agenda-parser"
  retention_in_days = 30
}

resource "aws_iam_role" "parser" {
  name = "${var.project_name}-agenda-parser"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Logs only: no VPC access, no database, no S3. The function reads text and calls a model.
resource "aws_iam_role_policy_attachment" "parser_logs" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser" {
  name = "call-bedrock"
  role = aws_iam_role.parser.id

  # "*" for now: any model, in any region. Narrowing it to the one inference profile and the
  # models it routes to is a discussion question of Lab 6.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock-mantle:CreateInference"]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  package_type  = "Image"
  image_uri     = local.image_uri
  architectures = ["arm64"]
  memory_size   = 512
  # A parse takes 2-8 s; one retry after an invalid answer can double that.
  timeout = 30
  role    = aws_iam_role.parser.arn

  # The backend's image with another app: Lambda Web Adapter passes each request to uvicorn.
  image_config {
    command = ["uvicorn", "app.ai.agenda_lambda:app", "--host", "0.0.0.0", "--port", "8000"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  environment {
    variables = {
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = var.bedrock_region
      BEDROCK_API          = var.bedrock_api
      PARSER_EFFORT        = var.parser_effort
      PARSER_FAKE          = tostring(var.parser_fake)
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      # The same token signing keys as the API (it gets them from make deploy-backend).
      COGNITO_JWKS                 = local.backend_env["COGNITO_JWKS"]
      AWS_LWA_PORT                 = "8000"
      AWS_LWA_READINESS_CHECK_PATH = "/health"
    }
  }

  # The app pipeline (make deploy-backend) moves the function to each new backend image.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Public, but every request needs a Cognito ID token (checked in the app) because every parse
# costs money. CORS lives here, not in the app: both would duplicate the headers.
resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = local.cors_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# A public function URL needs two statements in the function's policy. Their ids are the ones
# CloudFormation gave them, so they are imported as they are, condition included.
resource "aws_lambda_permission" "parser_url" {
  statement_id           = "spry-ai-FunctionUrlPermission-YwDBNNnjPU6m"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_invoke" {
  statement_id  = "spry-ai-FunctionInvokePermission-PVOtdDmngixj"
  function_name = aws_lambda_function.parser.function_name
  action        = "lambda:InvokeFunction"
  principal     = "*"
  # Allowed only through the function URL (lambda:InvokedViaFunctionUrl), not by a direct call.
  invoked_via_function_url = true
}

# The cheapest insurance in the course: an email when the account's cost for the month passes
# $5, and when it is forecast to.
resource "aws_budgets_budget" "monthly" {
  count = var.budget_email == "" ? 0 : 1

  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = "5.0"
  limit_unit   = "USD"

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
}

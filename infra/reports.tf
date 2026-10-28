# The weekly report (was infra/reports.yaml, Lab 5). EventBridge Scheduler (every Monday 07:00
# Kyiv) and `make report-now` put a message on an SQS queue; the report builder (the backend
# image, in the VPC) reads the database and saves reports/<week>.csv to S3 through a gateway
# endpoint; the ObjectCreated event starts the mailer (outside the VPC), which emails the file
# through SES.

# ------------------------------------------------------------------ Storage
# Every report ever built: never destroy or replace it.
resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "delete-old-reports"
    status = "Enabled"

    filter {
      prefix = "reports/"
    }

    expiration {
      days = 90
    }
  }
}

# Trigger 3: a new report file starts the mailer. In CloudFormation this needed a hand-built
# bucket name to break a cycle (bucket -> permission -> bucket); here the bucket, the permission
# and the notification are three resources, and the references order them.
resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_s3]
}

# Free: lets the builder (no NAT, no internet) reach S3 from inside the VPC. Without it
# PutObject hangs until the function times out.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [data.aws_route_table.main.id]
}

# -------------------------------------------------------------------- Queue
resource "aws_sqs_queue" "requests_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
  max_message_size          = 1048576 # 1 MiB, the current SQS default
}

resource "aws_sqs_queue" "requests" {
  name             = "${var.project_name}-report-requests"
  max_message_size = 1048576 # 1 MiB, the current SQS default
  # 6 x the builder's 60 s timeout: a message must not reappear while it is being built.
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.requests_dlq.arn
    maxReceiveCount     = 3
  })
}

# ------------------------------------------------------------------ Builder
resource "aws_cloudwatch_log_group" "builder" {
  name              = "/${var.project_name}/report-builder"
  retention_in_days = 7
}

resource "aws_iam_role" "builder" {
  name = "${var.project_name}-report-builder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "builder_vpc" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder" {
  name = "build-reports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      # The Lambda service polls the queue for the function (no network path needed).
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility",
        ]
        Resource = aws_sqs_queue.requests.arn
      },
    ]
  })
}

# The backend's own image, with app/reports/lambda_app.py instead of the API. Lambda Web
# Adapter (in the image) forwards non-HTTP events to POST /events.
resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  package_type  = "Image"
  image_uri     = local.image_uri
  architectures = ["arm64"]
  memory_size   = 512
  timeout       = 60
  role          = aws_iam_role.builder.arn

  image_config {
    command = ["uvicorn", "app.reports.lambda_app:app", "--host", "0.0.0.0", "--port", "8000"]
  }

  # Same subnets and security group as the API, so the database lets it in.
  vpc_config {
    subnet_ids         = local.subnet_ids
    security_group_ids = local.security_group_ids
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.builder.name
  }

  environment {
    variables = {
      # The API's own DATABASE_URL. sensitive() keeps it out of plan output (not out of state).
      DATABASE_URL                 = sensitive(local.backend_env["DATABASE_URL"])
      DB_POOL_SIZE                 = "1"
      DB_MAX_OVERFLOW              = "1"
      REPORTS_BUCKET               = aws_s3_bucket.reports.id
      REPORT_FAIL_WEEK             = var.fail_week
      AWS_LWA_PORT                 = "8000"
      AWS_LWA_READINESS_CHECK_PATH = "/health"
      AWS_LWA_PASS_THROUGH_PATH    = "/events"
      # A 500 from /events fails a direct invocation instead of looking like success.
      AWS_LWA_ERROR_STATUS_CODES = "500"
    }
  }

  # The app pipeline (make deploy-backend) moves the function to each new backend image.
  lifecycle {
    ignore_changes = [image_uri]
  }

  # A function in a VPC needs the ENI permissions before it can switch to this role.
  depends_on = [aws_iam_role_policy_attachment.builder_vpc]
}

# Trigger 2: one message at a time; failed messages are reported back, not raised.
resource "aws_lambda_event_source_mapping" "builder" {
  event_source_arn        = aws_sqs_queue.requests.arn
  function_name           = aws_lambda_function.builder.arn
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
}

# ----------------------------------------------------------------- Schedule
resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-report-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "send-report-requests"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.requests.arn
    }]
  })
}

# Trigger 1: a command on the queue every Monday morning. No week: the builder takes the
# previous ISO week.
resource "aws_scheduler_schedule" "weekly" {
  name                = "${var.project_name}-weekly-report"
  group_name          = "default"
  schedule_expression = var.schedule_expression
  # Without it the cron runs in UTC, and the report moves by an hour with daylight saving.
  schedule_expression_timezone = "Europe/Kyiv"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.requests.arn
    role_arn = aws_iam_role.scheduler.arn
    # Written out, not jsonencode(): the text must stay exactly as CloudFormation left it.
    input = "{\"week\": null, \"source\": \"schedule\"}"
  }
}

# ------------------------------------------------------------------- Mailer
resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/${var.project_name}/report-mailer"
  retention_in_days = 7
}

resource "aws_iam_role" "mailer" {
  name = "${var.project_name}-report-mailer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mailer_logs" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer" {
  name = "mail-reports"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read only: the mailer must never write into reports/ (it would trigger itself).
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.reports.arn}/reports/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
    ]
  })
}

# The code is infra/mailer/index.py (it was inline in the template).
data "archive_file" "mailer" {
  type        = "zip"
  source_file = "${path.module}/mailer/index.py"
  output_path = "${path.module}/.build/report-mailer.zip"
}

# Outside the VPC: it needs SES on the internet, and never touches the database.
resource "aws_lambda_function" "mailer" {
  function_name    = "${var.project_name}-report-mailer"
  runtime          = "python3.13"
  handler          = "index.handler"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 30
  role             = aws_iam_role.mailer.arn
  filename         = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.mailer.name
  }

  environment {
    variables = {
      REPORT_FROM = var.report_email
      REPORT_TO   = var.report_email
    }
  }
}

# Lets S3 invoke the mailer. The statement id is the one CloudFormation gave it, so the
# statement is imported, not added a second time.
resource "aws_lambda_permission" "mailer_s3" {
  statement_id   = "spry-reports-MailerS3Permission-EhVoiJ8wC8E6"
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.reports.arn
  source_account = local.account_id
}

# ---------------------------------------------------------------------- SES
# No domain of our own, so the identity is one email address: SES emails it a link to click.
# In the SES sandbox, mail goes only to verified addresses, which is this one.
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.report_email
}

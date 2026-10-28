# Everything the Makefile, the deploy scripts and the frontend build read
# (infra/common.sh: tf_output NAME = terraform -chdir=infra output -raw NAME).

output "region" {
  value = var.region
}

# ---------------------------------------------------------------- Auth
output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_domain" {
  description = "Cognito domain for the managed login page and OAuth redirects"
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "cognito_issuer" {
  description = "Issuer of the tokens; the backend checks it"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "cognito_google_enabled" {
  value = var.google_client_id == "" ? "false" : "true"
}

# ------------------------------------------------------------- Reports
output "reports_bucket" {
  value = aws_s3_bucket.reports.id
}

output "report_queue_url" {
  value = aws_sqs_queue.requests.url
}

output "report_dlq_url" {
  value = aws_sqs_queue.requests_dlq.url
}

output "report_builder_log_group" {
  value = aws_cloudwatch_log_group.builder.name
}

output "report_mailer_log_group" {
  value = aws_cloudwatch_log_group.mailer.name
}

# ------------------------------------------------------- Agenda parser
output "parser_url" {
  description = "Function URL without the trailing slash; the frontend is built against it"
  value       = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_log_group" {
  value = aws_cloudwatch_log_group.parser.name
}

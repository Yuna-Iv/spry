variable "project_name" {
  type        = string
  description = "Prefix of every resource name; also the PROJECT_NAME tag."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "project_name: lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "region" {
  type        = string
  description = "AWS region of the app (Bedrock may be in another one, see bedrock_region)."
}

# ---------------------------------------------------------------- Auth (auth.tf)
variable "google_client_id" {
  type        = string
  default     = ""
  description = "Google OAuth client id. Empty: no Google sign-in. Not a secret (the browser sees it)."
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client secret. Set it in the HCP Terraform workspace, never in a file."
}

# ------------------------------------------------------------- Reports (reports.tf)
variable "report_email" {
  type        = string
  description = "Sender and recipient of the weekly report (an SES email identity)."
}

variable "schedule_expression" {
  type        = string
  default     = "cron(0 7 ? * MON *)"
  description = "When the weekly report is built, in Europe/Kyiv time."
}

variable "fail_week" {
  type        = string
  default     = ""
  description = "The builder fails on purpose for this ISO week (to watch the dead-letter queue)."
}

# ------------------------------------------------------------ Agenda parser (ai.tf)
variable "parser_model" {
  type        = string
  description = "Bedrock model id, or an inference profile id with bedrock_api = runtime."
}

variable "bedrock_region" {
  type    = string
  default = "us-east-1"
}

variable "bedrock_api" {
  type        = string
  default     = "mantle"
  description = "mantle (bedrock-mantle, current Claude models) or runtime (bedrock-runtime InvokeModel)."

  validation {
    condition     = contains(["mantle", "runtime"], var.bedrock_api)
    error_message = "bedrock_api must be mantle or runtime."
  }
}

variable "parser_effort" {
  type        = string
  default     = "low"
  description = "Claude's effort setting (low ... max), or none for models without it."
}

variable "parser_fake" {
  type        = bool
  default     = false
  description = "true: the parser returns a fixed agenda and never calls the model."
}

variable "budget_email" {
  type        = string
  default     = ""
  description = "AWS Budgets emails this address when the month's cost passes $5. Empty: no budget."
}

variable "extra_cors_origins" {
  type        = list(string)
  default     = []
  description = "Origins allowed to call the parser besides the frontend's own addresses."
}

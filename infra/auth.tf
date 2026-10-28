# Cognito (was infra/auth.yaml, Lab 4): sign-in with email and password, a public app client for
# the SPA, a Cognito domain for OAuth, and Google as an identity provider when google_client_id
# is set.

# Every account that signed up lives here: never destroy or replace it. prevent_destroy makes a
# plan that would do so fail instead of running.
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Managed login (the hosted sign-in page) needs the Essentials tier; first 10,000 MAU are free.
  user_pool_tier      = "ESSENTIALS"
  deletion_protection = "INACTIVE"
  mfa_configuration   = "OFF"

  # Self sign-up stays on: anyone can create an account on the sign-in page.
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # Users sign in with their email; Cognito emails a code to verify it.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # A new email (profile page) takes effect only after its code is entered.
  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  username_configuration {
    case_sensitive = false
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    required                 = true
    mutable                  = true
    developer_only_attribute = false

    string_attribute_constraints {
      min_length = "0"
      max_length = "2048"
    }
  }

  # "name" is a standard attribute with the default settings, so it is not declared here:
  # Cognito has it anyway, and declaring it would make the provider try to add it again.

  # Mirrored by the signup form (frontend/src/pages/signup-page.tsx).
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_uppercase                = false
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Cognito's own sender: no SES setup, limited to about 50 emails a day.
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Meetings verification code"
    email_message        = "Your Meetings verification code is {####}"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Hosted domain for the OAuth endpoints (needed for Google). Prefixes are global.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.project_name}-${local.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id

  # Version 2 = the new managed login page (needs the branding below to show anything).
  managed_login_version = 2
}

resource "aws_cognito_identity_provider" "google" {
  count = var.google_client_id == "" ? 0 : 1

  user_pool_id  = aws_cognito_user_pool.main.id
  provider_name = "Google"
  provider_type = "Google"

  # Cognito fills in Google's endpoints itself; they are written out so the plan stays quiet.
  provider_details = {
    client_id                     = var.google_client_id
    client_secret                 = var.google_client_secret
    authorize_scopes              = "openid email profile"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    oidc_issuer                   = "https://accounts.google.com"
    token_request_method          = "POST"
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
  }

  attribute_mapping = {
    email          = "email"
    email_verified = "email_verified"
    name           = "name"
    username       = "sub"
  }
}

# Public client (no secret): the SPA talks to Cognito directly with SRP.
resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30
  auth_session_validity  = 3

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  # The reference to the provider also makes the client wait for it.
  supported_identity_providers = concat(["COGNITO"], aws_cognito_identity_provider.google[*].provider_name)

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  # "<origin>/login" for every origin of the app (local dev servers and CloudFront).
  callback_urls = [for url in local.app_urls : "${url}/login"]
  logout_urls   = [for url in local.app_urls : "${url}/login"]
}

# Default Cognito look for the managed login page of this app client.
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id                = aws_cognito_user_pool.main.id
  client_id                   = aws_cognito_user_pool_client.web.id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.main]
}

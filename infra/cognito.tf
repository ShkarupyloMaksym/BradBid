# =============================================================================
# COGNITO (User Authentication)
# Krок 3 - Cognito User Pool and App Client for SPA authentication
# =============================================================================

resource "aws_cognito_user_pool" "main" {
  name = "exchange-user-pool"

  auto_verified_attributes = ["email"]
  username_attributes      = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  schema {
    attribute_data_type      = "String"
    name                     = "email"
    required                 = true
    mutable                  = true
    string_attribute_constraints {
      min_length = 5
      max_length = 256
    }
  }

  tags = {
    Name = "exchange-user-pool"
  }
}

resource "aws_cognito_user_pool_client" "spa_client" {
  name         = "exchange-spa-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret                      = false
  explicit_auth_flows                  = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
  supported_identity_providers         = ["COGNITO"]
  
  # OAuth configuration for SPA
  allowed_oauth_flows                  = ["implicit", "code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  
  callback_urls = ["http://localhost:3000/callback", "https://${aws_cloudfront_distribution.spa.domain_name}/callback"]
  logout_urls   = ["http://localhost:3000/logout", "https://${aws_cloudfront_distribution.spa.domain_name}/logout"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "bradbid-exchange-${random_id.cognito_domain.hex}"
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "random_id" "cognito_domain" {
  byte_length = 4
}

output "cognito_user_pool_id" {
  description = "The ID of the Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  description = "The ID of the Cognito App Client for SPA"
  value       = aws_cognito_user_pool_client.spa_client.id
}

output "cognito_domain" {
  description = "The domain for Cognito hosted UI"
  value       = aws_cognito_user_pool_domain.main.domain
}

# =============================================================================
# CLOUDFRONT (CDN for SPA)
# Krок 4 - CloudFront distribution for SPA hosting
# =============================================================================

resource "aws_cloudfront_origin_access_control" "spa" {
  name                              = "spa-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "spa" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"  # Use only North America and Europe for cost savings

  origin {
    domain_name              = aws_s3_bucket.spa_bucket.bucket_regional_domain_name
    origin_id                = "S3-SPA"
    origin_access_control_id = aws_cloudfront_origin_access_control.spa.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-SPA"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Handle SPA routing (return index.html for all 404s)
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "exchange-spa-distribution"
  }
}

# S3 bucket for SPA hosting
resource "aws_s3_bucket" "spa_bucket" {
  bucket = "exchange-spa-${random_id.spa_bucket.hex}"
}

resource "random_id" "spa_bucket" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "spa_bucket" {
  bucket = aws_s3_bucket.spa_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "spa_bucket" {
  bucket = aws_s3_bucket.spa_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.spa_bucket.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.spa.arn
          }
        }
      }
    ]
  })
}

output "cloudfront_distribution_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.spa.domain_name
}

output "spa_bucket_name" {
  description = "S3 bucket name for SPA hosting"
  value       = aws_s3_bucket.spa_bucket.bucket
}

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ============================================================
# S3 BUCKET FOR CRL DISTRIBUTION
# ============================================================
resource "aws_s3_bucket" "crl_bucket" {
  bucket_prefix = "acme-pki-crl-"
  
  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "crl_bucket" {
  bucket = aws_s3_bucket.crl_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "crl_bucket_policy" {
  bucket = aws_s3_bucket.crl_bucket.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicReadCRL"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.crl_bucket.arn}/*"
      }
    ]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.crl_bucket]
}

# ============================================================
# S3 BUCKET FOR ROOT CA CERTIFICATE
# ============================================================
resource "aws_s3_bucket" "root_ca_bucket" {
  bucket_prefix = "acme-pki-root-"
  
  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "root_ca_bucket" {
  bucket = aws_s3_bucket.root_ca_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "root_ca_bucket_policy" {
  bucket = aws_s3_bucket.root_ca_bucket.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicReadRootCA"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.root_ca_bucket.arn}/*"
      }
    ]
  })
  
  depends_on = [aws_s3_bucket_public_access_block.root_ca_bucket]
}

# ============================================================
# ACM PRIVATE CA - INTERMEDIATE ONLY (Subordinate)
# Root CA is managed offline locally
# ============================================================
resource "aws_acmpca_certificate_authority" "intermediate_ca" {
  type = "SUBORDINATE"

  certificate_authority_configuration {
    key_algorithm     = "EC_secp384r1"
    signing_algorithm = "SHA384WITHECDSA"

    subject {
      country                  = var.country
      state                    = var.state
      locality                 = var.locality
      organization             = var.organization_name
      organizational_unit      = var.organizational_unit
      common_name              = "ACME Intermediate CA"
    }
  }

  revocation_configuration {
    crl_configuration {
      enabled            = true
      expiration_in_days = var.crl_validity_days
      s3_bucket_name     = aws_s3_bucket.crl_bucket.id
      s3_object_acl      = "PUBLIC_READ"
    }

    ocsp_configuration {
      enabled = true
    }
  }

  tags = merge(var.tags, {
    Name = "ACME-Intermediate-CA"
  })
  
  # Important: Mark as PENDING_CERTIFICATE until signed by local Root CA
  lifecycle {
    ignore_changes = [
      # Certificate is installed separately after signing
    ]
  }
}

# ============================================================
# OUTPUT: CSR for signing with local Root CA
# The CSR must be signed offline and then imported
# ============================================================

# Save CSR to local file for offline signing
resource "local_file" "intermediate_csr" {
  content  = aws_acmpca_certificate_authority.intermediate_ca.certificate_signing_request
  filename = "${path.module}/../intermediate_csr.pem"
}

# ============================================================
# PLACEHOLDER: Certificate import happens after signing
# Use the install_certificate.sh script after signing
# ============================================================

# Lambda execution role
resource "aws_iam_role" "lambda_role" {
  name = "acme-pki-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_acmpca" {
  name = "acme-pki-lambda-acmpca-policy"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "acm-pca:IssueCertificate",
          "acm-pca:GetCertificate",
          "acm-pca:GetCertificateAuthorityCertificate"
        ]
        Resource = aws_acmpca_certificate_authority.intermediate_ca.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.root_ca_bucket.arn}/*"
      }
    ]
  })
}

# Lambda function for enrollment
data "archive_file" "enroll_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/enroll.py"
  output_path = "${path.module}/../lambda/enroll.zip"
}

resource "aws_lambda_function" "enroll" {
  filename         = data.archive_file.enroll_lambda.output_path
  function_name    = "acme-pki-enroll"
  role             = aws_iam_role.lambda_role.arn
  handler          = "enroll.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  source_code_hash = data.archive_file.enroll_lambda.output_base64sha256
  
  environment {
    variables = {
      INTERMEDIATE_CA_ARN = aws_acmpca_certificate_authority.intermediate_ca.arn
      VALIDITY_DAYS       = var.subscriber_validity_days
    }
  }
  
  tags = var.tags
}

# Lambda function for Root CA retrieval
data "archive_file" "get_root_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/get_root.py"
  output_path = "${path.module}/../lambda/get_root.zip"
}

resource "aws_lambda_function" "get_root" {
  filename         = data.archive_file.get_root_lambda.output_path
  function_name    = "acme-pki-get-root"
  role             = aws_iam_role.lambda_role.arn
  handler          = "get_root.lambda_handler"
  runtime          = "python3.11"
  timeout          = 10
  source_code_hash = data.archive_file.get_root_lambda.output_base64sha256
  
  environment {
    variables = {
      ROOT_CA_BUCKET = aws_s3_bucket.root_ca_bucket.id
    }
  }
  
  tags = var.tags
}

# API Gateway
resource "aws_apigatewayv2_api" "pki_api" {
  name          = "acme-pki-api"
  protocol_type = "HTTP"
  
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["Content-Type"]
  }
  
  tags = var.tags
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.pki_api.id
  name        = "$default"
  auto_deploy = true
}

# Enroll endpoint
resource "aws_apigatewayv2_integration" "enroll" {
  api_id             = aws_apigatewayv2_api.pki_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.enroll.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "enroll" {
  api_id    = aws_apigatewayv2_api.pki_api.id
  route_key = "POST /enroll"
  target    = "integrations/${aws_apigatewayv2_integration.enroll.id}"
}

resource "aws_lambda_permission" "enroll" {
  statement_id  = "AllowAPIGatewayEnroll"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enroll.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.pki_api.execution_arn}/*/*"
}

# Root CA endpoint
resource "aws_apigatewayv2_integration" "get_root" {
  api_id             = aws_apigatewayv2_api.pki_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.get_root.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.pki_api.id
  route_key = "GET /root"
  target    = "integrations/${aws_apigatewayv2_integration.get_root.id}"
}

resource "aws_lambda_permission" "get_root" {
  statement_id  = "AllowAPIGatewayGetRoot"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_root.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.pki_api.execution_arn}/*/*"
}

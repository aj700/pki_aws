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

# Lambda policies
resource "aws_iam_role_policy" "lambda_acmpca" {
  name = "acmpca-access"
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
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "s3-access"
  role = aws_iam_role.lambda_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.root_ca_bucket.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Package Lambda functions
data "archive_file" "enroll_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/enroll.py"
  output_path = "${path.module}/../lambda/enroll.zip"
}

data "archive_file" "get_root_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/get_root.py"
  output_path = "${path.module}/../lambda/get_root.zip"
}

# Enroll Lambda function
resource "aws_lambda_function" "enroll" {
  filename         = data.archive_file.enroll_zip.output_path
  function_name    = "acme-pki-enroll"
  role             = aws_iam_role.lambda_role.arn
  handler          = "enroll.lambda_handler"
  source_code_hash = data.archive_file.enroll_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  
  environment {
    variables = {
      INTERMEDIATE_CA_ARN = aws_acmpca_certificate_authority.intermediate_ca.arn
      VALIDITY_DAYS       = var.subscriber_cert_validity_days
    }
  }
  
  tags = var.tags
  
  depends_on = [aws_acmpca_certificate_authority_certificate.intermediate_ca]
}

# Get Root Lambda function
resource "aws_lambda_function" "get_root" {
  filename         = data.archive_file.get_root_zip.output_path
  function_name    = "acme-pki-get-root"
  role             = aws_iam_role.lambda_role.arn
  handler          = "get_root.lambda_handler"
  source_code_hash = data.archive_file.get_root_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 10
  
  environment {
    variables = {
      ROOT_CA_BUCKET = aws_s3_bucket.root_ca_bucket.id
    }
  }
  
  tags = var.tags
}

# API Gateway permissions to invoke Lambda
resource "aws_lambda_permission" "enroll_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enroll.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pki_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_root_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_root.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.pki_api.execution_arn}/*/*"
}

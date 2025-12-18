# API Gateway REST API
resource "aws_api_gateway_rest_api" "pki_api" {
  name        = "ACME-PKI-API"
  description = "REST API for PKI operations (enrollment, revocation, root CA)"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  tags = var.tags
}

# /enroll endpoint
resource "aws_api_gateway_resource" "enroll" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  parent_id   = aws_api_gateway_rest_api.pki_api.root_resource_id
  path_part   = "enroll"
}

resource "aws_api_gateway_method" "enroll_post" {
  rest_api_id   = aws_api_gateway_rest_api.pki_api.id
  resource_id   = aws_api_gateway_resource.enroll.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "enroll_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.pki_api.id
  resource_id             = aws_api_gateway_resource.enroll.id
  http_method             = aws_api_gateway_method.enroll_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.enroll.invoke_arn
}

# /root endpoint
resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  parent_id   = aws_api_gateway_rest_api.pki_api.root_resource_id
  path_part   = "root"
}

resource "aws_api_gateway_method" "root_get" {
  rest_api_id   = aws_api_gateway_rest_api.pki_api.id
  resource_id   = aws_api_gateway_resource.root.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.pki_api.id
  resource_id             = aws_api_gateway_resource.root.id
  http_method             = aws_api_gateway_method.root_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.get_root.invoke_arn
}

# /crl endpoint - direct S3 proxy
resource "aws_api_gateway_resource" "crl" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  parent_id   = aws_api_gateway_rest_api.pki_api.root_resource_id
  path_part   = "crl"
}

resource "aws_api_gateway_method" "crl_get" {
  rest_api_id   = aws_api_gateway_rest_api.pki_api.id
  resource_id   = aws_api_gateway_resource.crl.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "crl_s3" {
  rest_api_id             = aws_api_gateway_rest_api.pki_api.id
  resource_id             = aws_api_gateway_resource.crl.id
  http_method             = aws_api_gateway_method.crl_get.http_method
  integration_http_method = "GET"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:s3:path/${aws_s3_bucket.crl_bucket.id}/crl/${aws_acmpca_certificate_authority.intermediate_ca.id}.crl"
  credentials             = aws_iam_role.api_gateway_s3.arn
}

resource "aws_api_gateway_method_response" "crl_200" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  resource_id = aws_api_gateway_resource.crl.id
  http_method = aws_api_gateway_method.crl_get.http_method
  status_code = "200"
  
  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration_response" "crl_200" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  resource_id = aws_api_gateway_resource.crl.id
  http_method = aws_api_gateway_method.crl_get.http_method
  status_code = aws_api_gateway_method_response.crl_200.status_code
  
  response_parameters = {
    "method.response.header.Content-Type" = "'application/pkix-crl'"
  }
  
  depends_on = [aws_api_gateway_integration.crl_s3]
}

# IAM role for API Gateway to access S3
resource "aws_iam_role" "api_gateway_s3" {
  name = "acme-pki-apigateway-s3-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  
  tags = var.tags
}

resource "aws_iam_role_policy" "api_gateway_s3" {
  name = "s3-read-access"
  role = aws_iam_role.api_gateway_s3.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${aws_s3_bucket.crl_bucket.arn}/*"]
      }
    ]
  })
}

# Deploy API
resource "aws_api_gateway_deployment" "pki_api" {
  rest_api_id = aws_api_gateway_rest_api.pki_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.enroll,
      aws_api_gateway_resource.root,
      aws_api_gateway_resource.crl,
      aws_api_gateway_method.enroll_post,
      aws_api_gateway_method.root_get,
      aws_api_gateway_method.crl_get,
      aws_api_gateway_integration.enroll_lambda,
      aws_api_gateway_integration.root_lambda,
      aws_api_gateway_integration.crl_s3,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
  
  depends_on = [
    aws_api_gateway_integration.enroll_lambda,
    aws_api_gateway_integration.root_lambda,
    aws_api_gateway_integration.crl_s3,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.pki_api.id
  rest_api_id   = aws_api_gateway_rest_api.pki_api.id
  stage_name    = "prod"
  
  tags = var.tags
}

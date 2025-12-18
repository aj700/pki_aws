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

# S3 bucket for CRL distribution
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

# Root CA
resource "aws_acmpca_certificate_authority" "root_ca" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "EC_secp384r1"
    signing_algorithm = "SHA384WITHECDSA"

    subject {
      country                  = var.country
      state                    = var.state
      locality                 = var.locality
      organization             = var.organization_name
      organizational_unit      = var.organizational_unit
      common_name              = "ACME Root CA"
    }
  }

  tags = merge(var.tags, {
    Name = "ACME-Root-CA"
  })
}

# Root CA certificate (self-signed)
resource "aws_acmpca_certificate" "root_ca_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.root_ca.certificate_signing_request
  signing_algorithm           = "SHA384WITHECDSA"

  template_arn = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = var.root_ca_validity_years
  }
}

# Install Root CA certificate
resource "aws_acmpca_certificate_authority_certificate" "root_ca" {
  certificate_authority_arn = aws_acmpca_certificate_authority.root_ca.arn
  certificate               = aws_acmpca_certificate.root_ca_cert.certificate
  certificate_chain         = aws_acmpca_certificate.root_ca_cert.certificate_chain
}

# Intermediate CA
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

  depends_on = [aws_acmpca_certificate_authority_certificate.root_ca]
}

# Sign Intermediate CA with Root CA
resource "aws_acmpca_certificate" "intermediate_ca_cert" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.root_ca.arn
  certificate_signing_request = aws_acmpca_certificate_authority.intermediate_ca.certificate_signing_request
  signing_algorithm           = "SHA384WITHECDSA"

  template_arn = "arn:aws:acm-pca:::template/SubordinateCACertificate_PathLen0/V1"

  validity {
    type  = "YEARS"
    value = var.intermediate_ca_validity_years
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.root_ca]
}

# Install Intermediate CA certificate
resource "aws_acmpca_certificate_authority_certificate" "intermediate_ca" {
  certificate_authority_arn = aws_acmpca_certificate_authority.intermediate_ca.arn
  certificate               = aws_acmpca_certificate.intermediate_ca_cert.certificate
  certificate_chain         = aws_acmpca_certificate.intermediate_ca_cert.certificate_chain
}

# S3 bucket for Root CA certificate distribution
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

# Upload Root CA certificate to S3
resource "aws_s3_object" "root_ca_cert" {
  bucket       = aws_s3_bucket.root_ca_bucket.id
  key          = "rootCA.crt"
  content      = aws_acmpca_certificate.root_ca_cert.certificate
  content_type = "application/x-pem-file"
  
  depends_on = [aws_s3_bucket_policy.root_ca_bucket_policy]
}

# Upload certificate chain to S3
resource "aws_s3_object" "ca_chain" {
  bucket       = aws_s3_bucket.root_ca_bucket.id
  key          = "ca-chain.crt"
  content      = "${aws_acmpca_certificate.intermediate_ca_cert.certificate}\n${aws_acmpca_certificate.root_ca_cert.certificate}"
  content_type = "application/x-pem-file"
  
  depends_on = [
    aws_s3_bucket_policy.root_ca_bucket_policy,
    aws_acmpca_certificate_authority_certificate.intermediate_ca
  ]
}

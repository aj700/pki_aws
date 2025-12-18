output "root_ca_arn" {
  description = "ARN of the Root CA"
  value       = aws_acmpca_certificate_authority.root_ca.arn
}

output "intermediate_ca_arn" {
  description = "ARN of the Intermediate CA"
  value       = aws_acmpca_certificate_authority.intermediate_ca.arn
}

output "crl_bucket_name" {
  description = "S3 bucket name for CRL distribution"
  value       = aws_s3_bucket.crl_bucket.id
}

output "crl_url" {
  description = "URL to download CRL"
  value       = "https://${aws_s3_bucket.crl_bucket.bucket_regional_domain_name}/crl/${aws_acmpca_certificate_authority.intermediate_ca.id}.crl"
}

output "root_ca_cert_url" {
  description = "URL to download Root CA certificate"
  value       = "https://${aws_s3_bucket.root_ca_bucket.bucket_regional_domain_name}/rootCA.crt"
}

output "ca_chain_url" {
  description = "URL to download full CA chain"
  value       = "https://${aws_s3_bucket.root_ca_bucket.bucket_regional_domain_name}/ca-chain.crt"
}

output "ocsp_url" {
  description = "OCSP responder URL"
  value       = aws_acmpca_certificate_authority.intermediate_ca.revocation_configuration[0].ocsp_configuration[0].ocsp_custom_cname
}

output "api_gateway_url" {
  description = "Base URL for PKI REST API"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "enroll_endpoint" {
  description = "POST endpoint for certificate enrollment"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/enroll"
}

output "root_endpoint" {
  description = "GET endpoint for Root CA certificate"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/root"
}

output "crl_endpoint" {
  description = "GET endpoint for CRL download"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/crl"
}

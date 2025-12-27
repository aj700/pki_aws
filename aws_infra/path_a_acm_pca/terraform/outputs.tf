output "intermediate_ca_arn" {
  description = "ARN of the ACM PCA Intermediate CA"
  value       = aws_acmpca_certificate_authority.intermediate_ca.arn
}

output "intermediate_ca_csr" {
  description = "CSR of the Intermediate CA - sign this with your offline Root CA"
  value       = aws_acmpca_certificate_authority.intermediate_ca.certificate_signing_request
  sensitive   = true
}

output "intermediate_csr_file" {
  description = "Path to the saved CSR file"
  value       = local_file.intermediate_csr.filename
}

output "api_gateway_url" {
  description = "API Gateway URL for PKI operations"
  value       = aws_apigatewayv2_api.pki_api.api_endpoint
}

output "enroll_endpoint" {
  description = "Endpoint for certificate enrollment"
  value       = "${aws_apigatewayv2_api.pki_api.api_endpoint}/enroll"
}

output "root_ca_endpoint" {
  description = "Endpoint to download Root CA certificate"
  value       = "${aws_apigatewayv2_api.pki_api.api_endpoint}/root"
}

output "crl_bucket" {
  description = "S3 bucket for CRL distribution"
  value       = aws_s3_bucket.crl_bucket.id
}

output "root_ca_bucket" {
  description = "S3 bucket for Root CA certificate"
  value       = aws_s3_bucket.root_ca_bucket.id
}

output "next_steps" {
  description = "Instructions for completing the setup"
  value       = <<-EOT
    
    ============================================
    NEXT STEPS - Sign the Intermediate CA
    ============================================
    
    1. The Intermediate CA CSR has been saved to:
       ${local_file.intermediate_csr.filename}
    
    2. Sign it with your offline Root CA:
       cd ../shared
       ./sign_intermediate.sh ../path_a_acm_pca/intermediate_csr.pem ../path_a_acm_pca/intermediate.crt
    
    3. Upload Root CA certificate to S3:
       aws s3 cp ../../pki_infra/rootCA/certs/rootCA.crt s3://${aws_s3_bucket.root_ca_bucket.id}/rootCA.crt
    
    4. Install the signed certificate:
       ./install_certificate.sh
    
    5. Test enrollment:
       curl -X POST ${aws_apigatewayv2_api.pki_api.api_endpoint}/enroll \\
         -H "Content-Type: application/x-pem-file" \\
         -d @test.csr
    
    ============================================
  EOT
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost"
  value       = "~$400 (ACM PCA Subordinate CA)"
}

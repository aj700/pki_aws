output "pki_server_public_ip" {
  description = "Public IP of the PKI server"
  value       = aws_eip.pki_server.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.pki_server.public_ip}"
}

output "api_base_url" {
  description = "Base URL for PKI API"
  value       = "http://${aws_eip.pki_server.public_ip}"
}

output "health_endpoint" {
  description = "Health check endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/health"
}

output "enroll_endpoint" {
  description = "Certificate enrollment endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/enroll"
}

output "root_ca_endpoint" {
  description = "Root CA download endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/root"
}

output "chain_endpoint" {
  description = "CA chain download endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/chain"
}

output "crl_endpoint" {
  description = "CRL download endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/crl/intermediate.crl"
}

output "next_steps" {
  description = "Instructions for completing the setup"
  value       = <<-EOT
    
    ============================================
    NEXT STEPS - Import Root CA Certificate
    ============================================
    
    1. Wait for EC2 setup to complete (~3-5 min):
       curl http://${aws_eip.pki_server.public_ip}/health
    
    2. SSH into the server:
       ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.pki_server.public_ip}
    
    3. Copy the Intermediate CA CSR:
       scp -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.pki_server.public_ip}:/opt/pki/intermediateCA/csr/interCA.csr ./intermediate_csr.pem
    
    4. Sign with your offline Root CA:
       cd ../shared
       ./sign_intermediate.sh intermediate_csr.pem intermediate.crt
    
    5. Upload the signed cert and Root CA:
       scp -i ~/.ssh/${var.key_name}.pem intermediate.crt ec2-user@${aws_eip.pki_server.public_ip}:/tmp/
       scp -i ~/.ssh/${var.key_name}.pem ../../Local_Root_CA/rootCA/certs/rootCA.crt ec2-user@${aws_eip.pki_server.public_ip}:/tmp/
    
    6. Install certificates (on EC2):
       sudo /opt/pki/scripts/import_signed_cert.sh /tmp/intermediate.crt /tmp/rootCA.crt
    
    ============================================
  EOT
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost"
  value       = "~$15 (EC2 t3.micro + EBS + EIP)"
}

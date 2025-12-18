output "pki_server_public_ip" {
  description = "Public IP of the PKI server"
  value       = aws_eip.pki_server.public_ip
}

output "pki_server_instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.pki_server.id
}

output "api_base_url" {
  description = "Base URL for PKI REST API"
  value       = "http://${aws_eip.pki_server.public_ip}"
}

output "enroll_endpoint" {
  description = "Certificate enrollment endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/enroll"
}

output "root_ca_endpoint" {
  description = "Root CA download endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/root"
}

output "crl_endpoint" {
  description = "CRL download endpoint"
  value       = "http://${aws_eip.pki_server.public_ip}/crl/intermediate.crl"
}

output "ssh_command" {
  description = "SSH command to connect to PKI server"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ec2-user@${aws_eip.pki_server.public_ip}"
}

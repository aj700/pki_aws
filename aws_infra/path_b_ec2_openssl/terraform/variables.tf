variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "EC2 instance type for PKI server"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key pair name for EC2 access"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"  # Restrict this in production
}

variable "organization_name" {
  description = "Organization name for certificate subjects"
  type        = string
  default     = "ACME Corporation"
}

variable "organizational_unit" {
  description = "Organizational unit for certificate subjects"
  type        = string
  default     = "ACME Security"
}

variable "country" {
  description = "Country code for certificate subjects"
  type        = string
  default     = "SE"
}

variable "state" {
  description = "State/Province for certificate subjects"
  type        = string
  default     = "Vastra Gotaland"
}

variable "locality" {
  description = "Locality for certificate subjects"
  type        = string
  default     = "Gothenburg"
}

variable "intermediate_ca_validity_days" {
  description = "Intermediate CA certificate validity in days"
  type        = number
  default     = 1825  # 5 years
}

variable "subscriber_cert_validity_days" {
  description = "Default subscriber certificate validity in days"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ACME-PKI"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Path        = "B-EC2-OpenSSL"
  }
}

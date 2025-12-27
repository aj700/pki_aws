variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-north-1"
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

variable "intermediate_ca_validity_years" {
  description = "Intermediate CA certificate validity in years"
  type        = number
  default     = 5
}

variable "subscriber_validity_days" {
  description = "Default subscriber certificate validity in days"
  type        = number
  default     = 365
}

variable "crl_validity_days" {
  description = "CRL validity in days"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "ACME-PKI"
    Environment = "Production"
    ManagedBy   = "Terraform"
    Path        = "A-ACM-PCA"
  }
}

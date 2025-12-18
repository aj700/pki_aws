# AWS PKI Infrastructure

Terraform configuration for deploying a complete PKI infrastructure in AWS using ACM Private CA.

## Architecture

- **Root CA**: P-384 ECDSA, 20-year validity, signs Intermediate CA
- **Intermediate CA**: P-384 ECDSA, 5-year validity, issues subscriber certs
- **API Gateway**: REST API for certificate operations
- **Lambda**: Enrollment and Root CA retrieval functions
- **S3**: CRL and Root CA certificate distribution

## REST API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/enroll` | POST | Submit CSR, receive subscriber + intermediate cert |
| `/root` | GET | Download Root CA certificate |
| `/crl` | GET | Download current CRL |

OCSP is available directly via the URL embedded in certificates (AIA extension).

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0

## Deployment

```bash
cd terraform

# Initialize
terraform init

# Review plan
terraform plan

# Deploy (WARNING: ~$800/month for 2 CAs)
terraform apply
```

## Post-Deployment Testing

```bash
# Get the API URL
API_URL=$(terraform output -raw api_gateway_url)

# Download Root CA
curl ${API_URL}/root -o rootCA.crt

# Enroll a certificate
openssl ecparam -name secp384r1 -genkey -noout -out test.key
openssl req -new -key test.key -out test.csr -subj "/CN=test.acme.com"
curl -X POST ${API_URL}/enroll \
  -H "Content-Type: application/x-pem-file" \
  -d @test.csr

# Download CRL
curl ${API_URL}/crl -o crl.der
```

## Cost Estimate

| Service | Monthly Cost |
|---------|--------------|
| ACM PCA Root CA | ~$400 |
| ACM PCA Intermediate CA | ~$400 |
| Lambda, API Gateway, S3 | < $5 |
| **Total** | **~$805** |

> **Tip**: Disable Root CA after setup to reduce to ~$400/month.

## Cleanup

```bash
terraform destroy
```

# Path A: Hybrid ACM PCA Deployment Guide

Deploy a production-grade PKI using AWS ACM Private CA for the Intermediate CA, while keeping the Root CA offline.

## Architecture

```
LOCAL (Offline)                    AWS Cloud
┌──────────────┐                  ┌─────────────────────────┐
│  Root CA     │ ── signs ──────► │  Intermediate CA        │
│  (P-384)     │   (one-time)     │  (ACM PCA - HSM)        │
│  Air-gapped  │                  │  FIPS 140-2 Level 3     │
└──────────────┘                  └───────────┬─────────────┘
                                              │
                                  ┌───────────▼─────────────┐
                                  │  API Gateway + Lambda    │
                                  │  /enroll, /root          │
                                  └───────────┬─────────────┘
                                              │
                                  ┌───────────▼─────────────┐
                                  │  S3: CRL + Root CA       │
                                  │  OCSP: AWS Managed       │
                                  └─────────────────────────┘
```

## Cost: ~$400/month

| Service | Cost |
|---------|------|
| ACM PCA (Subordinate) | ~$400 |
| Lambda + API Gateway | < $5 |
| S3 | < $1 |

---

## Prerequisites

- [ ] AWS CLI configured
- [ ] Terraform >= 1.0
- [ ] Root CA generated (see `pki_infra/rootCA/`)

---

## Step 1: Deploy Infrastructure

```bash
cd aws_infra/path_a_acm_pca/terraform

terraform init
terraform plan
terraform apply
```

This creates:
- ACM PCA Intermediate CA (PENDING_CERTIFICATE status)
- S3 buckets for CRL and Root CA
- Lambda functions + API Gateway

---

## Step 2: Download the Intermediate CA CSR

The CSR is automatically saved to `intermediate_csr.pem`:

```bash
# View the CSR
openssl req -in ../intermediate_csr.pem -noout -text
```

---

## Step 3: Sign with Offline Root CA

⚠️ **This step should be done on an air-gapped machine with the Root CA**

```bash
cd aws_infra/shared

./sign_intermediate.sh \
    ../path_a_acm_pca/intermediate_csr.pem \
    ../path_a_acm_pca/intermediate.crt \
    1825  # 5 years validity
```

---

## Step 4: Install the Signed Certificate

```bash
cd aws_infra/path_a_acm_pca

chmod +x install_certificate.sh
./install_certificate.sh
```

This will:
- Import the certificate into ACM PCA
- Upload Root CA to S3
- Verify CA is ACTIVE

---

## Step 5: Test the API

```bash
# Get API URL
API_URL=$(cd terraform && terraform output -raw api_gateway_url)

# Download Root CA
curl $API_URL/root -o rootCA.crt

# Generate test key and CSR
openssl ecparam -name secp384r1 -genkey -noout -out test.key
openssl req -new -key test.key -out test.csr \
    -subj "/C=SE/ST=Vastra Gotaland/O=ACME Corporation/CN=test.acme.com"

# Enroll certificate
curl -X POST $API_URL/enroll \
    -H "Content-Type: application/x-pem-file" \
    -d @test.csr | jq .
```

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/root` | GET | Download Root CA certificate |
| `/enroll` | POST | Submit CSR, receive certificate |

---

## Cleanup

```bash
cd terraform
terraform destroy
```

⚠️ This will permanently delete the Intermediate CA and all issued certificates.

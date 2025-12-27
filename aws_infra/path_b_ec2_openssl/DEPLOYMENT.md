# Path B: EC2 + OpenSSL Deployment Guide

Deploy a cost-effective PKI using EC2 with OpenSSL, keeping the Root CA offline.

## Architecture

```
LOCAL (Offline)                    AWS (EC2)
┌──────────────┐                  ┌─────────────────────────┐
│  Root CA     │ ── signs ──────► │  Intermediate CA        │
│  (P-384)     │   (one-time)     │  (OpenSSL)              │
│  Air-gapped  │                  │  Software keys (EBS)    │
└──────────────┘                  └───────────┬─────────────┘
                                              │
                                  ┌───────────▼─────────────┐
                                  │  NGINX + Flask API      │
                                  │  /enroll, /root, /csr   │
                                  └───────────┬─────────────┘
                                              │
                                  ┌───────────▼─────────────┐
                                  │  CRL served via NGINX   │
                                  └─────────────────────────┘
```

## Cost: ~$15/month

| Service | Cost |
|---------|------|
| EC2 t3.micro | ~$8 |
| EBS 20GB gp3 | ~$2 |
| Elastic IP | Free |
| Data Transfer | ~$5 |

---

## Prerequisites

- [ ] AWS CLI configured
- [ ] Terraform >= 1.0
- [ ] EC2 Key Pair created
- [ ] Root CA generated (see `pki_infra/rootCA/`)

---

## Step 1: Configure Variables

```bash
cd aws_infra/path_b_ec2_openssl/terraform

# Create tfvars file
cat > terraform.tfvars << EOF
key_name         = "your-key-name"
allowed_ssh_cidr = "YOUR_IP/32"  # Get with: curl ifconfig.me
EOF
```

---

## Step 2: Deploy EC2

```bash
terraform init
terraform plan
terraform apply
```

Wait ~3-5 minutes for EC2 setup to complete.

---

## Step 3: Check Status

```bash
PKI_IP=$(terraform output -raw pki_server_public_ip)

# Wait until ready (status will show pending_certificates)
curl http://$PKI_IP/health
```

Expected:
```json
{"status": "pending_certificates", "message": "Import signed certificates first"}
```

---

## Step 4: Download Intermediate CA CSR

```bash
# From API
curl http://$PKI_IP/csr -o intermediate_csr.pem

# Or via SCP
scp -i ~/.ssh/your-key.pem ec2-user@$PKI_IP:/opt/pki/intermediateCA/csr/interCA.csr ./intermediate_csr.pem
```

---

## Step 5: Sign with Offline Root CA

⚠️ **This step should be done on an air-gapped machine**

```bash
cd aws_infra/shared

./sign_intermediate.sh \
    ../path_b_ec2_openssl/intermediate_csr.pem \
    ../path_b_ec2_openssl/intermediate.crt \
    1825  # 5 years
```

---

## Step 6: Upload Signed Certificates

```bash
scp -i ~/.ssh/your-key.pem intermediate.crt ec2-user@$PKI_IP:/tmp/
scp -i ~/.ssh/your-key.pem ../../pki_infra/rootCA/certs/rootCA.crt ec2-user@$PKI_IP:/tmp/
```

---

## Step 7: Install Certificates

```bash
# SSH into EC2
ssh -i ~/.ssh/your-key.pem ec2-user@$PKI_IP

# Run import script
sudo /opt/pki/scripts/import_signed_cert.sh /tmp/intermediate.crt /tmp/rootCA.crt

# Verify
curl http://localhost/health
```

Expected:
```json
{"status": "healthy", "certificates_installed": true}
```

---

## Step 8: Test Enrollment

```bash
# From your local machine
PKI_IP=$(cd terraform && terraform output -raw pki_server_public_ip)

# Download CA chain
curl http://$PKI_IP/chain -o ca-chain.crt

# Generate test CSR
openssl ecparam -name secp384r1 -genkey -noout -out test.key
openssl req -new -key test.key -out test.csr \
    -subj "/C=SE/ST=Vastra Gotaland/O=ACME Corporation/CN=test.acme.com"

# Enroll
curl -X POST http://$PKI_IP/enroll \
    -H "Content-Type: application/x-pem-file" \
    -d @test.csr | jq -r '.subscriber_cert' > test.crt

# Verify
openssl verify -CAfile ca-chain.crt test.crt
```

---

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check + certificate status |
| `/root` | GET | Download Root CA certificate |
| `/chain` | GET | Download full CA chain |
| `/csr` | GET | Download Intermediate CA CSR |
| `/crl/intermediate.crl` | GET | Download CRL |
| `/enroll` | POST | Submit CSR, receive certificate |

---

## Cleanup

```bash
cd terraform
terraform destroy
```

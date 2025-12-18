# EC2 + OpenSSL PKI Deployment Guide

Step-by-step guide to deploy the ACME PKI infrastructure on AWS using EC2 and OpenSSL.

## Prerequisites

- [ ] AWS CLI installed and configured
- [ ] Terraform >= 1.0 installed
- [ ] An EC2 Key Pair created in your target region

---

## Step 1: Verify Prerequisites

```bash
# Check AWS CLI
aws --version
aws sts get-caller-identity

# Check Terraform
terraform --version
```

**Expected output:** Your AWS account ID and Terraform version.

---

## Step 2: Create EC2 Key Pair (if needed)

```bash
# Create key pair (replace 'acme-pki-key' with your preferred name)
aws ec2 create-key-pair \
    --key-name acme-pki-key \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/acme-pki-key.pem

chmod 400 ~/.ssh/acme-pki-key.pem
```

---

## Step 3: Configure Terraform Variables

```bash
cd aws_infra/ec2_openssl/terraform

# Copy example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

**Required changes in `terraform.tfvars`:**
```hcl
key_name = "acme-pki-key"  # Your key pair name from Step 2
allowed_ssh_cidr = "YOUR_IP/32"  # Your public IP for SSH access
```

**To find your public IP:**
```bash
curl ifconfig.me
```

---

## Step 4: Initialize Terraform

```bash
terraform init
```

**Expected output:**
```
Terraform has been successfully initialized!
```

---

## Step 5: Review Deployment Plan

```bash
terraform plan
```

**Review the resources to be created:**
- 1 EC2 instance (t3.micro)
- 1 Security Group
- 1 Elastic IP
- 1 IAM Role + Instance Profile

---

## Step 6: Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Expected output (after ~2-3 minutes):**
```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

api_base_url = "http://X.X.X.X"
enroll_endpoint = "http://X.X.X.X/enroll"
root_ca_endpoint = "http://X.X.X.X/root"
...
```

---

## Step 7: Wait for PKI Setup to Complete

The EC2 instance runs a setup script on first boot. Wait ~3-5 minutes for it to complete.

```bash
# Get the instance IP
PKI_IP=$(terraform output -raw pki_server_public_ip)

# Check if API is ready
curl http://$PKI_IP/health
```

**Expected output when ready:**
```json
{"status": "healthy"}
```

**If not ready yet, check setup logs:**
```bash
# SSH into the instance
ssh -i ~/.ssh/acme-pki-key.pem ec2-user@$PKI_IP

# View setup log
sudo tail -f /var/log/pki-setup.log
```

---

## Step 8: Verify Deployment

### 8a. Download Root CA Certificate
```bash
curl http://$PKI_IP/root -o rootCA.crt
openssl x509 -in rootCA.crt -text -noout | head -20
```

### 8b. Download CA Chain
```bash
curl http://$PKI_IP/chain -o ca-chain.crt
```

### 8c. Test Certificate Enrollment
```bash
# Generate a test key and CSR
openssl ecparam -name secp384r1 -genkey -noout -out test.key
openssl req -new -key test.key -out test.csr \
    -subj "/C=SE/ST=Vastra Gotaland/O=ACME Corporation/CN=test.acme.com"

# Enroll certificate
curl -X POST http://$PKI_IP/enroll \
    -H "Content-Type: application/x-pem-file" \
    -d @test.csr | jq .
```

**Expected output:**
```json
{
  "subscriber_cert": "-----BEGIN CERTIFICATE-----...",
  "intermediate_cert": "-----BEGIN CERTIFICATE-----...",
  "certificate_chain": "..."
}
```

### 8d. Verify Certificate Chain
```bash
# Save the subscriber cert
curl -X POST http://$PKI_IP/enroll \
    -H "Content-Type: application/x-pem-file" \
    -d @test.csr | jq -r '.subscriber_cert' > test.crt

# Verify chain
openssl verify -CAfile ca-chain.crt test.crt
```

**Expected output:**
```
test.crt: OK
```

---

## Step 9: (Optional) Enable HTTPS

For production, you should enable HTTPS. You can:

1. **Use AWS Certificate Manager + Load Balancer**
2. **Use Let's Encrypt on the EC2 instance**

```bash
# SSH into instance
ssh -i ~/.ssh/acme-pki-key.pem ec2-user@$PKI_IP

# Install certbot
sudo dnf install -y certbot python3-certbot-nginx

# Get certificate (requires domain pointing to instance)
sudo certbot --nginx -d pki.yourdomain.com
```

---

## API Reference

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/root` | GET | Download Root CA certificate |
| `/chain` | GET | Download full CA chain |
| `/crl/intermediate.crl` | GET | Download CRL |
| `/enroll` | POST | Submit CSR, receive certificate |

---

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

Type `yes` when prompted.

---

## Troubleshooting

### API returns 502 Bad Gateway
The Flask API may not have started yet. Wait 2-3 minutes and retry.

```bash
# Check API service status
ssh -i ~/.ssh/acme-pki-key.pem ec2-user@$PKI_IP
sudo systemctl status pki-api
sudo journalctl -u pki-api -f
```

### Cannot SSH to instance
Verify your `allowed_ssh_cidr` includes your current IP:
```bash
curl ifconfig.me
```

### Certificate enrollment fails
Check the CA database isn't locked:
```bash
ssh -i ~/.ssh/acme-pki-key.pem ec2-user@$PKI_IP
sudo cat /opt/pki/intermediateCA/index
```

---

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| EC2 t3.micro | ~$8 |
| EBS 20GB gp3 | ~$2 |
| Elastic IP | Free (while attached) |
| Data Transfer | ~$1-5 |
| **Total** | **~$11-15/month** |

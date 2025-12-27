# AWS PKI Infrastructure

Two deployment paths for production-grade PKI infrastructure, both sharing a **single offline Root CA**.

## Architecture

```
                     LOCAL / OFFLINE
                     ┌───────────────────────┐
                     │ Root CA (P-384)       │
                     │ Local_Root_CA/rootCA/ │
                     │ - Kept air-gapped     │
                     │ - Signs both paths    │
                     └───────────┬───────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
              ▼                  │                  ▼
┌─────────────────────────┐      │     ┌─────────────────────────┐
│  PATH A: Production     │      │     │  PATH B: Dev/Test       │
│  ~$400/month            │      │     │  ~$15/month             │
├─────────────────────────┤      │     ├─────────────────────────┤
│  ACM Private CA         │      │     │  EC2 + OpenSSL          │
│  HSM-backed (FIPS L3)   │      │     │  Software keys          │
│  Managed OCSP + CRL     │      │     │  Manual CRL             │
│  API Gateway + Lambda   │      │     │  NGINX + Flask          │
└─────────────────────────┘      │     └─────────────────────────┘
              │                  │                  │
              └──────────────────┼──────────────────┘
                                 │
                     Subscribers trust the
                     SAME Root CA
```

## Quick Start

### Path A: Hybrid ACM PCA (Production)

```bash
cd path_a_acm_pca/terraform
terraform init && terraform apply

# Then sign the Intermediate CSR with your offline Root CA
# See path_a_acm_pca/DEPLOYMENT.md for full instructions
```

### Path B: EC2 + OpenSSL (Dev/Test)

```bash
cd path_b_ec2_openssl/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your key name and IP

terraform init && terraform apply

# Then sign the Intermediate CSR with your offline Root CA
# See path_b_ec2_openssl/DEPLOYMENT.md for full instructions
```

## Directory Structure

```
AWS_Intermediate_CA/
├── shared/                     # Common resources
│   ├── sign_intermediate.sh    # Script to sign Intermediate CSR
│   └── root_ca_setup.md        # Root CA management guide
│
├── path_a_acm_pca/            # Production path (~$400/mo)
│   ├── terraform/             # ACM PCA Intermediate only
│   ├── lambda/                # Enrollment functions
│   ├── install_certificate.sh # Import signed cert
│   └── DEPLOYMENT.md          # Step-by-step guide
│
└── path_b_ec2_openssl/        # Dev/Test path (~$15/mo)
    ├── terraform/             # EC2 + OpenSSL
    ├── scripts/               # user_data.sh for EC2 setup
    └── DEPLOYMENT.md          # Step-by-step guide
```

## Comparison

| Aspect | Path A (ACM PCA) | Path B (EC2) |
|--------|------------------|--------------|
| **Cost** | ~$400/month | ~$15/month |
| **Key Security** | HSM (FIPS 140-2 L3) | Software (EBS) |
| **OCSP** | ✅ AWS Managed | ❌ Manual |
| **CRL** | ✅ Auto-publish | Manual script |
| **HA/DR** | Multi-AZ | Single EC2 |
| **Best For** | Production | Dev/Test |

## Root CA

Both paths use your offline Root CA located at `../Local_Root_CA/rootCA/`.

See [shared/root_ca_setup.md](shared/root_ca_setup.md) for Root CA management instructions.

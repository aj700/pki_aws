#!/bin/bash
# ============================================================
# Install Signed Intermediate CA Certificate into ACM PCA
# Run this after signing the CSR with your offline Root CA
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERT_FILE="${1:-$SCRIPT_DIR/intermediate.crt}"
ROOT_CERT="${2:-$SCRIPT_DIR/../../Local_Root_CA/rootCA/certs/rootCA.crt}"

# Get the CA ARN from Terraform
cd "$SCRIPT_DIR/terraform"
CA_ARN=$(terraform output -raw intermediate_ca_arn 2>/dev/null || echo "")
ROOT_BUCKET=$(terraform output -raw root_ca_bucket 2>/dev/null || echo "")

if [ -z "$CA_ARN" ]; then
    echo -e "${RED}Error: Could not get Intermediate CA ARN from Terraform${NC}"
    echo "Make sure you have run 'terraform apply' first"
    exit 1
fi

if [ ! -f "$CERT_FILE" ]; then
    echo -e "${RED}Error: Signed certificate not found: $CERT_FILE${NC}"
    echo ""
    echo "Please sign the Intermediate CA CSR first:"
    echo "  cd ../shared"
    echo "  ./sign_intermediate.sh ../path_a_acm_pca/intermediate_csr.pem ../path_a_acm_pca/intermediate.crt"
    exit 1
fi

if [ ! -f "$ROOT_CERT" ]; then
    echo -e "${RED}Error: Root CA certificate not found: $ROOT_CERT${NC}"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Installing Intermediate CA Certificate${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "CA ARN:         $CA_ARN"
echo "Certificate:    $CERT_FILE"
echo "Root CA:        $ROOT_CERT"
echo ""

# Display certificate details
echo -e "${GREEN}Certificate Subject:${NC}"
openssl x509 -in "$CERT_FILE" -noout -subject -issuer
echo ""

# Confirm
read -p "Install this certificate into ACM PCA? (y/N) " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# Read certificate and chain
CERT_BODY=$(cat "$CERT_FILE")
CERT_CHAIN=$(cat "$ROOT_CERT")

echo ""
echo -e "${GREEN}Installing certificate into ACM PCA...${NC}"

aws acm-pca import-certificate-authority-certificate \
    --certificate-authority-arn "$CA_ARN" \
    --certificate "$CERT_BODY" \
    --certificate-chain "$CERT_CHAIN"

echo ""
echo -e "${GREEN}Certificate installed successfully!${NC}"

# Upload Root CA to S3
if [ -n "$ROOT_BUCKET" ]; then
    echo ""
    echo -e "${GREEN}Uploading Root CA certificate to S3...${NC}"
    aws s3 cp "$ROOT_CERT" "s3://$ROOT_BUCKET/rootCA.crt" \
        --content-type "application/x-pem-file"
    echo "Root CA uploaded to: s3://$ROOT_BUCKET/rootCA.crt"
fi

# Verify CA status
echo ""
echo -e "${GREEN}Verifying CA status...${NC}"
STATUS=$(aws acm-pca describe-certificate-authority \
    --certificate-authority-arn "$CA_ARN" \
    --query 'CertificateAuthority.Status' \
    --output text)

echo "CA Status: $STATUS"

if [ "$STATUS" == "ACTIVE" ]; then
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Intermediate CA is now ACTIVE!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "You can now enroll certificates using the API."
else
    echo -e "${YELLOW}Warning: CA status is $STATUS, expected ACTIVE${NC}"
fi

#!/bin/bash
# ============================================================
# Sign Intermediate CA CSR with Local Root CA
# This script is used by both deployment paths
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

usage() {
    echo "Usage: $0 <csr_file> <output_cert_file> [validity_days]"
    echo ""
    echo "Arguments:"
    echo "  csr_file         Path to the Intermediate CA CSR (PEM format)"
    echo "  output_cert_file Path where signed certificate will be written"
    echo "  validity_days    Certificate validity (default: 1825 = 5 years)"
    echo ""
    echo "Environment variables:"
    echo "  ROOT_CA_DIR      Path to Root CA directory (default: ../../Local_Root_CA/rootCA)"
    exit 1
}

# Check arguments
if [ $# -lt 2 ]; then
    usage
fi

CSR_FILE="$1"
OUTPUT_CERT="$2"
VALIDITY_DAYS="${3:-1825}"

# Find Root CA directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_CA_DIR="${ROOT_CA_DIR:-$SCRIPT_DIR/../../Local_Root_CA/rootCA}"

# Validate Root CA exists
if [ ! -f "$ROOT_CA_DIR/private/rootCA_p384.key" ]; then
    echo -e "${RED}Error: Root CA private key not found at $ROOT_CA_DIR/private/rootCA_p384.key${NC}"
    echo "Make sure you have generated the Root CA first using Local_Root_CA/rootCA"
    exit 1
fi

if [ ! -f "$ROOT_CA_DIR/certs/rootCA.crt" ]; then
    echo -e "${RED}Error: Root CA certificate not found at $ROOT_CA_DIR/certs/rootCA.crt${NC}"
    exit 1
fi

if [ ! -f "$ROOT_CA_DIR/rootCA.conf" ]; then
    echo -e "${RED}Error: Root CA config not found at $ROOT_CA_DIR/rootCA.conf${NC}"
    exit 1
fi

# Validate CSR exists
if [ ! -f "$CSR_FILE" ]; then
    echo -e "${RED}Error: CSR file not found: $CSR_FILE${NC}"
    exit 1
fi

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Signing Intermediate CA CSR${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""
echo "Root CA:        $ROOT_CA_DIR"
echo "CSR File:       $CSR_FILE"
echo "Output Cert:    $OUTPUT_CERT"
echo "Validity:       $VALIDITY_DAYS days"
echo ""

# Display CSR details
echo -e "${GREEN}CSR Subject:${NC}"
openssl req -in "$CSR_FILE" -noout -subject
echo ""

# Prompt for confirmation
read -p "Sign this CSR with the Root CA? (y/N) " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

# Sign the CSR
echo ""
echo -e "${GREEN}Signing CSR...${NC}"

cd "$ROOT_CA_DIR"

openssl ca -config rootCA.conf \
    -extensions v3_intermediate_ca \
    -days "$VALIDITY_DAYS" \
    -notext -md sha384 \
    -in "$CSR_FILE" \
    -out "$OUTPUT_CERT"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Intermediate CA certificate created!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Certificate saved to: $OUTPUT_CERT"
echo ""

# Display certificate details
echo -e "${GREEN}Certificate Details:${NC}"
openssl x509 -in "$OUTPUT_CERT" -noout -subject -issuer -dates
echo ""

# Verify the chain
echo -e "${GREEN}Verifying certificate chain...${NC}"
openssl verify -CAfile "$ROOT_CA_DIR/certs/rootCA.crt" "$OUTPUT_CERT"

echo ""
echo -e "${GREEN}Done!${NC}"

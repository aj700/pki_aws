# Root CA Management Guide

This guide explains how to manage the shared offline Root CA used by both AWS deployment paths.

## Root CA Location

The Root CA is located at `Local_Root_CA/rootCA/` and should be kept **offline** (air-gapped) whenever possible.

## Initial Setup

If you haven't already generated the Root CA, follow these steps:

```bash
cd Local_Root_CA/rootCA

# Generate P-384 ECDSA key pair
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out private/rootCA_p384.key
chmod 400 private/rootCA_p384.key

# Initialize database files
echo 1000 > serial
touch index
echo 1000 > crlnumber

# Generate self-signed Root CA certificate (20+ years validity)
openssl req -config rootCA.conf -key private/rootCA_p384.key \
    -new -x509 -days 7500 -extensions v3_ca -out certs/rootCA.crt
```

## Signing an Intermediate CA

When deploying either Path A (ACM PCA) or Path B (EC2+OpenSSL), you'll need to sign the Intermediate CA's CSR with this Root CA.

Use the shared script:

```bash
cd AWS_Intermediate_CA/shared

# Sign an Intermediate CA CSR
./sign_intermediate.sh <path_to_csr.pem> <output_cert.crt> [validity_days]

# Example for Path A (ACM PCA):
./sign_intermediate.sh ../path_a_acm_pca/intermediate_csr.pem ../path_a_acm_pca/intermediate.crt 1825

# Example for Path B (EC2+OpenSSL):
./sign_intermediate.sh ../path_b_ec2_openssl/intermediate_csr.pem ../path_b_ec2_openssl/intermediate.crt 1825
```

## Security Best Practices

1. **Air-gap the Root CA**: Never connect the machine with Root CA keys to the internet
2. **Backup securely**: Store encrypted backups in multiple secure locations
3. **Access control**: Limit access to Root CA keys to authorized personnel only
4. **Audit logging**: Log all Root CA signing operations
5. **Key ceremony**: Follow a documented procedure for all signing operations

## Distributing the Root CA Certificate

After any deployment, upload the Root CA certificate to accessible locations:

```bash
# Copy to S3 (for Path A)
aws s3 cp Local_Root_CA/rootCA/certs/rootCA.crt s3://your-bucket/rootCA.crt \
    --content-type "application/x-pem-file"

# The EC2 deployment (Path B) serves it automatically via the API
```

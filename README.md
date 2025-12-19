# Reference PKI Infrastructure in AWS

This project demonstrates the implementation of a Public Key Infrastructure (PKI) using the Elliptic Curve Digital Signature Algorithm (ECDSA) with the P-384 curve.
The setup includes a Root CA, Intermediate CA, and subscriber certificates, providing a complete chain of trust.

## Overview

The P-384 curve (also known as secp384r1) provides a strong foundation for modern PKI implementations. P-384 offers 192-bit security strength, which is considered secure for sensitive applications and aligns with requirements for classified information (NSA Suite B).

### Why P-384 (secp384r1)?

1. **Strong Security**
   - Provides 192-bit security level, equivalent to 7680-bit RSA
   - Approved for SECRET level classification (NSA Suite B)
   - Well-studied and analyzed curve with no known practical attacks

2. **Performance**
   - Significantly faster than RSA for equivalent security levels
   - Smaller key sizes (384 bits vs 7680 bits for equivalent RSA)
   - Reduced bandwidth and storage requirements for certificates

3. **Compliance & Interoperability**
   - NIST standardized curve
   - Widely supported across cryptographic libraries and hardware
   - Compatible with TLS 1.2/1.3, X.509 certificates, and code signing

4. **Recommended for**
   - High-security TLS/SSL certificates
   - Code signing certificates
   - Document signing
   - Automotive PKI (ISO 21434)
   - IoT device authentication

### Directory Structure
```
pqc_PKI/
├── PKIsubscriber/
│   ├── certs/
│   ├── csr/
│   └── private/
├── intermediateCA/
│   ├── certs/
│   ├── csr/
│   ├── newcerts/
│   └── private/
└── rootCA/
    ├── certs/
    ├── crl/
    ├── newcerts/
    ├── private/
    └── rootCA.conf
```

## Implementation Steps

### 1. Create Directory Structure
```bash
mkdir -p pqc_PKI/{rootCA,intermediateCA,PKIsubscriber}
cd pqc_PKI
mkdir -p rootCA/{certs,crl,newcerts,private}
mkdir -p intermediateCA/{certs,csr,newcerts,private}
mkdir -p PKIsubscriber/{certs,csr,private}
```

### 2. Generate Root CA

```bash
# Generate P-384 ECDSA key pair
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out rootCA/private/rootCA_p384.key

# Create configuration file rootCA.conf
# (Configuration content provided below)

# Initialize database files
echo 1000 > rootCA/serial
touch rootCA/index
echo 1000 > rootCA/crlnumber

# Generate and sign root certificate
openssl req -config rootCA/rootCA.conf -key rootCA/private/rootCA_p384.key \
    -new -x509 -days 7500 -extensions v3_ca -out rootCA/certs/rootCA.crt
```

### 3. Generate Intermediate CA

```bash
# Generate P-384 ECDSA key pair
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out intermediateCA/private/intermediateCA_p384.key

# Initialize database files
echo 1000 > intermediateCA/serial
touch intermediateCA/index
echo 1000 > intermediateCA/crlnumber

# Create CSR
openssl req -config intermediateCA/interCA.conf \
    -key intermediateCA/private/intermediateCA_p384.key \
    -new -out intermediateCA/csr/interCA.csr

# Sign intermediate certificate using Root CA
openssl ca -config rootCA/rootCA.conf -extensions v3_intermediate_ca \
    -days 1825 -notext -md sha384 \
    -in intermediateCA/csr/interCA.csr \
    -out intermediateCA/certs/interCA.crt
```

### 4. Generate Subscriber Certificates

This example creates two subscriber certificates with different purposes:

#### 4a. TLS Certificate (Cloud Service)

```bash
# Generate P-384 ECDSA key pair for TLS
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out PKIsubscriber/private/tls_p384.key

# Create CSR
openssl req -config PKIsubscriber/tls_subscriber.conf \
    -key PKIsubscriber/private/tls_p384.key \
    -new -out PKIsubscriber/csr/tls.csr

# Sign TLS certificate using Intermediate CA
openssl ca -config intermediateCA/interCA.conf -extensions tls_cert \
    -days 365 -notext -md sha384 \
    -in PKIsubscriber/csr/tls.csr \
    -out PKIsubscriber/certs/tls.crt
```

#### 4b. Encryption Certificate (Data Protection)

```bash
# Generate P-384 ECDSA key pair for encryption
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out PKIsubscriber/private/encryption_p384.key

# Create CSR
openssl req -config PKIsubscriber/encryption_subscriber.conf \
    -key PKIsubscriber/private/encryption_p384.key \
    -new -out PKIsubscriber/csr/encryption.csr

# Sign encryption certificate using Intermediate CA
openssl ca -config intermediateCA/interCA.conf -extensions encryption_cert \
    -days 365 -notext -md sha384 \
    -in PKIsubscriber/csr/encryption.csr \
    -out PKIsubscriber/certs/encryption.crt
```

## Configuration Files

### Root CA Configuration (rootCA.conf)
```ini
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /home/user/pqc_PKI/rootCA
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

private_key       = $dir/private/rootCA_p384.key
certificate       = $dir/certs/rootCA.crt

crlnumber         = $dir/crlnumber
crl               = $dir/crl/rootca.crl
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha384
name_opt          = ca_default
cert_opt          = ca_default
default_days      = 7500
preserve          = no
policy            = policy_strict

[ policy_strict ]
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress           = optional

[ req ]
default_bits        = 384
distinguished_name  = req_distinguished_name
string_mask        = utf8only
default_md         = sha384
x509_extensions    = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName            = State or Province Name
localityName                   = Locality Name
0.organizationName             = Organization Name
organizationalUnitName         = Organizational Unit Name
commonName                     = Common Name
emailAddress                   = Email Address

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
```

### Intermediate CA Configuration (interCA.conf)
```ini
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /home/user/pqc_PKI/intermediateCA
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

private_key       = $dir/private/intermediateCA_p384.key
certificate       = $dir/certs/interCA.crt

crlnumber         = $dir/crlnumber
crl               = $dir/crl/intermediate.crl
crl_extensions    = crl_ext
default_crl_days  = 30

default_md        = sha384
name_opt         = ca_default
cert_opt         = ca_default
default_days     = 375
preserve         = no
policy           = policy_loose

[ policy_loose ]
countryName             = match
stateOrProvinceName     = match
localityName            = optional
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress           = optional

[ req ]
default_bits        = 384
distinguished_name  = req_distinguished_name
string_mask        = utf8only
default_md         = sha384

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName            = State or Province Name
localityName                   = Locality Name
0.organizationName             = Organization Name
organizationalUnitName         = Organizational Unit Name
commonName                     = Common Name
emailAddress                   = Email Address

[ subscriber_cert ]
basicConstraints = CA:FALSE
subjectAltName = DNS:www.acme-corp.com
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth, codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer

[ tls_cert ]
basicConstraints = CA:FALSE
subjectAltName = DNS:api.acme-cloud.com, DNS:*.acme-cloud.com
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer

[ encryption_cert ]
basicConstraints = CA:FALSE
keyUsage = critical, keyAgreement
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
```

### TLS Subscriber Configuration (tls_subscriber.conf)
```ini
[ req ]
default_bits = 384
prompt = no
default_md = sha384
distinguished_name = dn

[ dn ]
C = SE
ST = Vastra Gotaland
L = Gothenburg
O = ACME Corporation
OU = ACME Cloud Services
CN = api.acme-cloud.com
```

### Encryption Subscriber Configuration (encryption_subscriber.conf)
```ini
[ req ]
default_bits = 384
prompt = no
default_md = sha384
distinguished_name = dn

[ dn ]
C = SE
ST = Vastra Gotaland
L = Gothenburg
O = ACME Corporation
OU = ACME Data Protection
CN = ACME Data Encryption Service
```

## Create Subscriber Certificate Chain for Distribution

```bash
# Create PKCS#7 bundle for TLS certificate distribution
openssl crl2pkcs7 -nocrl \
    -certfile PKIsubscriber/certs/tls.crt \
    -certfile intermediateCA/certs/interCA.crt \
    -out tls_cert_chain.p7b

# Create PKCS#7 bundle for encryption certificate distribution
openssl crl2pkcs7 -nocrl \
    -certfile PKIsubscriber/certs/encryption.crt \
    -certfile intermediateCA/certs/interCA.crt \
    -out encryption_cert_chain.p7b
```

## Certificate Chain Verification

```bash
# Verify the TLS certificate chain
openssl verify -show_chain -CAfile rootCA/certs/rootCA.crt \
    -untrusted intermediateCA/certs/interCA.crt \
    PKIsubscriber/certs/tls.crt

# Verify the encryption certificate chain
openssl verify -show_chain -CAfile rootCA/certs/rootCA.crt \
    -untrusted intermediateCA/certs/interCA.crt \
    PKIsubscriber/certs/encryption.crt
```

Expected output (TLS certificate):
```
PKIsubscriber/certs/tls.crt: OK
Chain:
depth=0: C = SE, ST = Vastra Gotaland, L = Gothenburg, O = ACME Corporation, OU = ACME Cloud Services, CN = api.acme-cloud.com
depth=1: C = SE, ST = Vastra Gotaland, O = ACME Corporation, OU = ACME Security, CN = ACME Intermediate CA
depth=2: C = SE, ST = Vastra Gotaland, L = Gothenburg, O = ACME Corporation, OU = ACME Security, CN = ACME Root CA
```

## Viewing Certificate Details

```bash
# View certificate details
openssl x509 -in PKIsubscriber/certs/PKIsubscriber.crt -text -noout

# View key details
openssl ec -in PKIsubscriber/private/PKIsubscriber_p384.key -text -noout
```

## Security Considerations

1. **Key Storage**
   - Private keys must be stored securely and CA keys shall be offline
   - Use appropriate access control permissions for all private key files (chmod 400)
   - Consider using HSM (Hardware Security Module) for production CA keys

2. **Certificate Management**
   - Implement regular certificate validation, renewal and revocation procedures
   - Maintain CRL (Certificate Revocation List) or OCSP for revocation checking

3. **Recommended Key Usage**
   - Root CA: 7500 days (20+ years), kept offline
   - Intermediate CA: 1825 days (5 years)
   - Subscriber: 365 days (1 year)

## Algorithm Comparison

| Property | P-384 (ECDSA) | RSA-3072 |
|----------|---------------|----------|
| Key Size | 384 bits | 3072 bits |
| Signature Size | ~96 bytes | 384 bytes |
| Security Level | 192 bits | ~128 bits |
| Sign Speed | Fast | Moderate |
| Verify Speed | Fast | Fast |

## License

This project is open source and licensed under the MIT License, a copy is available in the same repo.
You are free to use it for commercial or private use.

## References

1. [NIST FIPS 186-5 - Digital Signature Standard](https://csrc.nist.gov/publications/detail/fips/186/5/final)
2. [RFC 5480 - Elliptic Curve Cryptography Subject Public Key Information](https://datatracker.ietf.org/doc/html/rfc5480)
3. [OpenSSL EC Documentation](https://www.openssl.org/docs/man3.0/man1/openssl-ec.html)
4. [NIST SP 800-57 - Recommendation for Key Management](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final)

## Contributing

Please do share refinements, upgrades etc via pull requests.

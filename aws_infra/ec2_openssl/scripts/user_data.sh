#!/bin/bash
set -e

# ============================================================
# ACME PKI Server Setup Script
# This script runs on first boot to configure the PKI server
# ============================================================

exec > >(tee /var/log/pki-setup.log) 2>&1
echo "Starting PKI server setup at $(date)"

# Variables from Terraform
ORGANIZATION="${organization}"
ORG_UNIT="${org_unit}"
COUNTRY="${country}"
STATE="${state}"
LOCALITY="${locality}"
ROOT_VALIDITY="${root_validity}"
INTER_VALIDITY="${inter_validity}"
SUB_VALIDITY="${sub_validity}"

# Install dependencies
echo "Installing dependencies..."
dnf update -y
dnf install -y openssl nginx python3 python3-pip jq

# Create PKI directory structure
echo "Creating PKI directory structure..."
PKI_HOME="/opt/pki"
mkdir -p $PKI_HOME/{rootCA,intermediateCA,PKIsubscriber}/{certs,crl,newcerts,private,csr}
chmod 700 $PKI_HOME/*/private

# ============================================================
# ROOT CA CONFIGURATION
# ============================================================
cat > $PKI_HOME/rootCA/rootCA.conf << 'ROOTCONF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /opt/pki/rootCA
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
default_days      = ROOT_VALIDITY_PLACEHOLDER
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
prompt             = no

[ req_distinguished_name ]
countryName                     = COUNTRY_PLACEHOLDER
stateOrProvinceName             = STATE_PLACEHOLDER
localityName                    = LOCALITY_PLACEHOLDER
0.organizationName              = ORG_PLACEHOLDER
organizationalUnitName          = OU_PLACEHOLDER
commonName                      = ACME Root CA

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

[ crl_ext ]
authorityKeyIdentifier = keyid:always
ROOTCONF

# Replace placeholders
sed -i "s/ROOT_VALIDITY_PLACEHOLDER/$ROOT_VALIDITY/g" $PKI_HOME/rootCA/rootCA.conf
sed -i "s/COUNTRY_PLACEHOLDER/$COUNTRY/g" $PKI_HOME/rootCA/rootCA.conf
sed -i "s/STATE_PLACEHOLDER/$STATE/g" $PKI_HOME/rootCA/rootCA.conf
sed -i "s/LOCALITY_PLACEHOLDER/$LOCALITY/g" $PKI_HOME/rootCA/rootCA.conf
sed -i "s/ORG_PLACEHOLDER/$ORGANIZATION/g" $PKI_HOME/rootCA/rootCA.conf
sed -i "s/OU_PLACEHOLDER/$ORG_UNIT/g" $PKI_HOME/rootCA/rootCA.conf

# ============================================================
# INTERMEDIATE CA CONFIGURATION
# ============================================================
cat > $PKI_HOME/intermediateCA/interCA.conf << 'INTERCONF'
[ ca ]
default_ca = CA_default

[ CA_default ]
dir               = /opt/pki/intermediateCA
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
default_crl_days  = 7

default_md        = sha384
name_opt         = ca_default
cert_opt         = ca_default
default_days     = SUB_VALIDITY_PLACEHOLDER
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
prompt             = no

[ req_distinguished_name ]
countryName                     = COUNTRY_PLACEHOLDER
stateOrProvinceName             = STATE_PLACEHOLDER
localityName                    = LOCALITY_PLACEHOLDER
0.organizationName              = ORG_PLACEHOLDER
organizationalUnitName          = OU_PLACEHOLDER
commonName                      = ACME Intermediate CA

[ tls_cert ]
basicConstraints = CA:FALSE
subjectAltName = $ENV::SAN
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
crlDistributionPoints = URI:http://HOSTNAME_PLACEHOLDER/crl/intermediate.crl

[ encryption_cert ]
basicConstraints = CA:FALSE
keyUsage = critical, keyAgreement
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
crlDistributionPoints = URI:http://HOSTNAME_PLACEHOLDER/crl/intermediate.crl

[ crl_ext ]
authorityKeyIdentifier = keyid:always
INTERCONF

# Replace placeholders
sed -i "s/SUB_VALIDITY_PLACEHOLDER/$SUB_VALIDITY/g" $PKI_HOME/intermediateCA/interCA.conf
sed -i "s/COUNTRY_PLACEHOLDER/$COUNTRY/g" $PKI_HOME/intermediateCA/interCA.conf
sed -i "s/STATE_PLACEHOLDER/$STATE/g" $PKI_HOME/intermediateCA/interCA.conf
sed -i "s/LOCALITY_PLACEHOLDER/$LOCALITY/g" $PKI_HOME/intermediateCA/interCA.conf
sed -i "s/ORG_PLACEHOLDER/$ORGANIZATION/g" $PKI_HOME/intermediateCA/interCA.conf
sed -i "s/OU_PLACEHOLDER/$ORG_UNIT/g" $PKI_HOME/intermediateCA/interCA.conf

# Get public hostname for CRL distribution point
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)
sed -i "s/HOSTNAME_PLACEHOLDER/$PUBLIC_IP/g" $PKI_HOME/intermediateCA/interCA.conf

# ============================================================
# GENERATE PKI
# ============================================================
echo "Generating Root CA..."
cd $PKI_HOME/rootCA
echo 1000 > serial
touch index
echo 1000 > crlnumber

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out private/rootCA_p384.key
chmod 400 private/rootCA_p384.key

openssl req -config rootCA.conf -key private/rootCA_p384.key \
    -new -x509 -days $ROOT_VALIDITY -extensions v3_ca \
    -out certs/rootCA.crt

echo "Generating Intermediate CA..."
cd $PKI_HOME/intermediateCA
echo 1000 > serial
touch index
echo 1000 > crlnumber

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out private/intermediateCA_p384.key
chmod 400 private/intermediateCA_p384.key

openssl req -config interCA.conf -key private/intermediateCA_p384.key \
    -new -out csr/interCA.csr

openssl ca -config $PKI_HOME/rootCA/rootCA.conf -extensions v3_intermediate_ca \
    -days $INTER_VALIDITY -notext -md sha384 -batch \
    -in csr/interCA.csr -out certs/interCA.crt

# Generate initial CRL
openssl ca -config interCA.conf -gencrl -out crl/intermediate.crl

# Create CA chain
cat certs/interCA.crt $PKI_HOME/rootCA/certs/rootCA.crt > certs/ca-chain.crt

echo "Verifying certificate chain..."
openssl verify -CAfile $PKI_HOME/rootCA/certs/rootCA.crt certs/interCA.crt

# ============================================================
# REST API (Flask)
# ============================================================
echo "Setting up REST API..."
pip3 install flask gunicorn

cat > /opt/pki/api.py << 'APICODE'
from flask import Flask, request, jsonify, send_file
import subprocess
import tempfile
import os
import uuid

app = Flask(__name__)
PKI_HOME = "/opt/pki"

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

@app.route('/root', methods=['GET'])
def get_root():
    return send_file(
        f"{PKI_HOME}/rootCA/certs/rootCA.crt",
        mimetype='application/x-pem-file',
        as_attachment=True,
        download_name='rootCA.crt'
    )

@app.route('/chain', methods=['GET'])
def get_chain():
    return send_file(
        f"{PKI_HOME}/intermediateCA/certs/ca-chain.crt",
        mimetype='application/x-pem-file',
        as_attachment=True,
        download_name='ca-chain.crt'
    )

@app.route('/crl', methods=['GET'])
def get_crl():
    return send_file(
        f"{PKI_HOME}/intermediateCA/crl/intermediate.crl",
        mimetype='application/pkix-crl',
        as_attachment=True,
        download_name='intermediate.crl'
    )

@app.route('/enroll', methods=['POST'])
def enroll():
    try:
        csr_pem = request.get_data(as_text=True)
        if not csr_pem.strip().startswith('-----BEGIN CERTIFICATE REQUEST-----'):
            return jsonify({"error": "Invalid CSR format"}), 400
        
        # Save CSR to temp file
        csr_id = str(uuid.uuid4())[:8]
        csr_path = f"/tmp/csr_{csr_id}.pem"
        cert_path = f"/tmp/cert_{csr_id}.pem"
        
        with open(csr_path, 'w') as f:
            f.write(csr_pem)
        
        # Extract CN from CSR for SAN
        result = subprocess.run(
            ['openssl', 'req', '-in', csr_path, '-noout', '-subject'],
            capture_output=True, text=True
        )
        cn = "localhost"
        for part in result.stdout.split(','):
            if 'CN' in part or 'CN=' in part:
                cn = part.split('=')[-1].strip()
                break
        
        # Sign certificate
        env = os.environ.copy()
        env['SAN'] = f"DNS:{cn}"
        
        result = subprocess.run([
            'openssl', 'ca',
            '-config', f'{PKI_HOME}/intermediateCA/interCA.conf',
            '-extensions', 'tls_cert',
            '-days', '365',
            '-notext', '-md', 'sha384', '-batch',
            '-in', csr_path,
            '-out', cert_path
        ], capture_output=True, text=True, env=env)
        
        if result.returncode != 0:
            return jsonify({"error": f"Signing failed: {result.stderr}"}), 500
        
        with open(cert_path, 'r') as f:
            subscriber_cert = f.read()
        
        with open(f"{PKI_HOME}/intermediateCA/certs/interCA.crt", 'r') as f:
            intermediate_cert = f.read()
        
        # Cleanup
        os.remove(csr_path)
        os.remove(cert_path)
        
        return jsonify({
            "subscriber_cert": subscriber_cert,
            "intermediate_cert": intermediate_cert,
            "certificate_chain": subscriber_cert + intermediate_cert
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APICODE

# Create systemd service for API
cat > /etc/systemd/system/pki-api.service << 'SVCFILE'
[Unit]
Description=PKI REST API
After=network.target

[Service]
User=root
WorkingDirectory=/opt/pki
ExecStart=/usr/local/bin/gunicorn -w 2 -b 127.0.0.1:5000 api:app
Restart=always

[Install]
WantedBy=multi-user.target
SVCFILE

# ============================================================
# NGINX REVERSE PROXY
# ============================================================
echo "Configuring Nginx..."
cat > /etc/nginx/conf.d/pki.conf << 'NGINXCONF'
server {
    listen 80;
    server_name _;
    
    # CRL distribution
    location /crl/ {
        alias /opt/pki/intermediateCA/crl/;
        add_header Content-Type application/pkix-crl;
    }
    
    # Root CA download
    location /root {
        proxy_pass http://127.0.0.1:5000/root;
    }
    
    # CA chain download
    location /chain {
        proxy_pass http://127.0.0.1:5000/chain;
    }
    
    # Health check
    location /health {
        proxy_pass http://127.0.0.1:5000/health;
    }
    
    # Certificate enrollment
    location /enroll {
        proxy_pass http://127.0.0.1:5000/enroll;
        proxy_set_header Content-Type $content_type;
    }
}
NGINXCONF

# Remove default nginx config
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

# Start services
systemctl daemon-reload
systemctl enable pki-api nginx
systemctl start pki-api nginx

echo "PKI server setup complete at $(date)"
echo "API available at http://$PUBLIC_IP/"

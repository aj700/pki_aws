#!/bin/bash
set -e

# ============================================================
# ACME PKI Server Setup Script (Hybrid Mode)
# This script sets up Intermediate CA only - Root CA is external
# ============================================================

exec > >(tee /var/log/pki-setup.log) 2>&1
echo "Starting PKI server setup (Hybrid Mode) at $(date)"

# Variables from Terraform
ORGANIZATION="${organization}"
ORG_UNIT="${org_unit}"
COUNTRY="${country}"
STATE="${state}"
LOCALITY="${locality}"
INTER_VALIDITY="${inter_validity}"
SUB_VALIDITY="${sub_validity}"

# Install dependencies
echo "Installing dependencies..."
dnf update -y
dnf install -y openssl nginx python3 python3-pip jq

# Create PKI directory structure
echo "Creating PKI directory structure..."
PKI_HOME="/opt/pki"
mkdir -p $PKI_HOME/{rootCA/certs,intermediateCA,PKIsubscriber,scripts}/{certs,crl,newcerts,private,csr}
chmod 700 $PKI_HOME/intermediateCA/private

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
# GENERATE INTERMEDIATE CA KEY AND CSR (NOT CERTIFICATE!)
# Certificate will be signed by external Root CA
# ============================================================
echo "Generating Intermediate CA key and CSR..."
cd $PKI_HOME/intermediateCA
echo 1000 > serial
touch index
echo 1000 > crlnumber

openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 \
    -out private/intermediateCA_p384.key
chmod 400 private/intermediateCA_p384.key

# Generate CSR for signing by external Root CA
openssl req -config interCA.conf -key private/intermediateCA_p384.key \
    -new -out csr/interCA.csr

echo "Intermediate CA CSR created: $PKI_HOME/intermediateCA/csr/interCA.csr"
echo ""
echo "=========================================="
echo "IMPORTANT: Sign this CSR with your Root CA"
echo "=========================================="

# ============================================================
# CREATE IMPORT SCRIPT for signed certificate
# ============================================================
cat > $PKI_HOME/scripts/import_signed_cert.sh << 'IMPORTSCRIPT'
#!/bin/bash
set -e

SIGNED_CERT="$1"
ROOT_CA_CERT="$2"

if [ -z "$SIGNED_CERT" ] || [ -z "$ROOT_CA_CERT" ]; then
    echo "Usage: $0 <signed_intermediate.crt> <rootCA.crt>"
    exit 1
fi

PKI_HOME="/opt/pki"

echo "Importing certificates..."

# Copy the signed certificate
cp "$SIGNED_CERT" $PKI_HOME/intermediateCA/certs/interCA.crt

# Copy Root CA certificate (for serving via API)
cp "$ROOT_CA_CERT" $PKI_HOME/rootCA/certs/rootCA.crt

# Create CA chain
cat $PKI_HOME/intermediateCA/certs/interCA.crt $PKI_HOME/rootCA/certs/rootCA.crt > $PKI_HOME/intermediateCA/certs/ca-chain.crt

# Generate initial CRL
cd $PKI_HOME/intermediateCA
openssl ca -config interCA.conf -gencrl -out crl/intermediate.crl

# Verify the chain
echo ""
echo "Verifying certificate chain..."
openssl verify -CAfile $PKI_HOME/rootCA/certs/rootCA.crt $PKI_HOME/intermediateCA/certs/interCA.crt

echo ""
echo "=========================================="
echo "Certificates imported successfully!"
echo "=========================================="
echo ""
echo "PKI server is now ready for enrollment."
echo "Test: curl http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)/health"
IMPORTSCRIPT

chmod +x $PKI_HOME/scripts/import_signed_cert.sh

# ============================================================
# REST API (Flask) - Works after certificates are imported
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

def check_certs_installed():
    """Check if Root and Intermediate certs are installed."""
    root_exists = os.path.exists(f"{PKI_HOME}/rootCA/certs/rootCA.crt")
    inter_exists = os.path.exists(f"{PKI_HOME}/intermediateCA/certs/interCA.crt")
    return root_exists and inter_exists

@app.route('/health', methods=['GET'])
def health():
    certs_ready = check_certs_installed()
    status = "healthy" if certs_ready else "pending_certificates"
    return jsonify({
        "status": status,
        "certificates_installed": certs_ready,
        "message": "Ready for enrollment" if certs_ready else "Import signed certificates first"
    })

@app.route('/root', methods=['GET'])
def get_root():
    cert_path = f"{PKI_HOME}/rootCA/certs/rootCA.crt"
    if not os.path.exists(cert_path):
        return jsonify({"error": "Root CA certificate not installed"}), 404
    return send_file(
        cert_path,
        mimetype='application/x-pem-file',
        as_attachment=True,
        download_name='rootCA.crt'
    )

@app.route('/chain', methods=['GET'])
def get_chain():
    chain_path = f"{PKI_HOME}/intermediateCA/certs/ca-chain.crt"
    if not os.path.exists(chain_path):
        return jsonify({"error": "CA chain not installed"}), 404
    return send_file(
        chain_path,
        mimetype='application/x-pem-file',
        as_attachment=True,
        download_name='ca-chain.crt'
    )

@app.route('/crl', methods=['GET'])
def get_crl():
    crl_path = f"{PKI_HOME}/intermediateCA/crl/intermediate.crl"
    if not os.path.exists(crl_path):
        return jsonify({"error": "CRL not available"}), 404
    return send_file(
        crl_path,
        mimetype='application/pkix-crl',
        as_attachment=True,
        download_name='intermediate.crl'
    )

@app.route('/csr', methods=['GET'])
def get_intermediate_csr():
    """Download the Intermediate CA CSR for signing."""
    csr_path = f"{PKI_HOME}/intermediateCA/csr/interCA.csr"
    return send_file(
        csr_path,
        mimetype='application/x-pem-file',
        as_attachment=True,
        download_name='intermediate_csr.pem'
    )

@app.route('/enroll', methods=['POST'])
def enroll():
    if not check_certs_installed():
        return jsonify({
            "error": "PKI not ready. Import signed certificates first.",
            "help": "See /health for status"
        }), 503
    
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
    
    # API endpoints
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
NGINXCONF

# Remove default nginx config
rm -f /etc/nginx/conf.d/default.conf 2>/dev/null || true

# Start services
systemctl daemon-reload
systemctl enable pki-api nginx
systemctl start pki-api nginx

echo ""
echo "=========================================="
echo "PKI server setup complete at $(date)"
echo "=========================================="
echo ""
echo "NEXT STEPS:"
echo "1. Download the Intermediate CA CSR:"
echo "   curl http://$PUBLIC_IP/csr -o intermediate_csr.pem"
echo ""
echo "2. Sign it with your offline Root CA"
echo ""
echo "3. Import the signed certificate:"
echo "   sudo /opt/pki/scripts/import_signed_cert.sh signed_intermediate.crt rootCA.crt"
echo ""
echo "4. Test: curl http://$PUBLIC_IP/health"
echo ""

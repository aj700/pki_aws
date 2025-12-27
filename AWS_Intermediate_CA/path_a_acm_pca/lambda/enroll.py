"""
Lambda function for certificate enrollment.
Receives a CSR, signs it using ACM PCA, returns subscriber cert + intermediate cert.
"""

import json
import boto3
import base64
import os
from datetime import datetime, timedelta

acmpca = boto3.client('acm-pca')

# Environment variables
INTERMEDIATE_CA_ARN = os.environ.get('INTERMEDIATE_CA_ARN')
VALIDITY_DAYS = int(os.environ.get('VALIDITY_DAYS', '365'))


def lambda_handler(event, context):
    """
    Handle certificate enrollment request.
    
    Expected input:
    - Body: PEM-encoded CSR
    - Headers: Content-Type: application/x-pem-file
    
    Returns:
    - subscriber_cert: PEM-encoded subscriber certificate
    - intermediate_cert: PEM-encoded intermediate CA certificate
    - certificate_chain: Full chain (subscriber + intermediate)
    """
    
    try:
        # Extract CSR from request body
        if 'body' not in event:
            return error_response(400, "Missing request body")
        
        csr_pem = event['body']
        
        # Handle base64 encoding from API Gateway
        if event.get('isBase64Encoded', False):
            csr_pem = base64.b64decode(csr_pem).decode('utf-8')
        
        # Validate CSR format
        if not csr_pem.strip().startswith('-----BEGIN CERTIFICATE REQUEST-----'):
            return error_response(400, "Invalid CSR format. Expected PEM-encoded CSR.")
        
        # Issue certificate using ACM PCA
        response = acmpca.issue_certificate(
            CertificateAuthorityArn=INTERMEDIATE_CA_ARN,
            Csr=csr_pem.encode('utf-8'),
            SigningAlgorithm='SHA384WITHECDSA',
            Validity={
                'Value': VALIDITY_DAYS,
                'Type': 'DAYS'
            },
            # Use EndEntityCertificate template for TLS server certs
            TemplateArn='arn:aws:acm-pca:::template/EndEntityCertificate/V1'
        )
        
        certificate_arn = response['CertificateArn']
        
        # Wait for certificate to be issued (usually instant)
        waiter = acmpca.get_waiter('certificate_issued')
        waiter.wait(
            CertificateAuthorityArn=INTERMEDIATE_CA_ARN,
            CertificateArn=certificate_arn,
            WaiterConfig={'Delay': 1, 'MaxAttempts': 10}
        )
        
        # Retrieve the certificate
        cert_response = acmpca.get_certificate(
            CertificateAuthorityArn=INTERMEDIATE_CA_ARN,
            CertificateArn=certificate_arn
        )
        
        subscriber_cert = cert_response['Certificate']
        certificate_chain = cert_response.get('CertificateChain', '')
        
        # Get intermediate CA certificate separately for clarity
        ca_response = acmpca.get_certificate_authority_certificate(
            CertificateAuthorityArn=INTERMEDIATE_CA_ARN
        )
        intermediate_cert = ca_response['Certificate']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'subscriber_cert': subscriber_cert,
                'intermediate_cert': intermediate_cert,
                'certificate_chain': f"{subscriber_cert}\n{certificate_chain}",
                'certificate_arn': certificate_arn,
                'expires_at': (datetime.utcnow() + timedelta(days=VALIDITY_DAYS)).isoformat() + 'Z'
            })
        }
        
    except acmpca.exceptions.MalformedCSRException:
        return error_response(400, "Malformed CSR. Please check CSR format and signature.")
    
    except acmpca.exceptions.InvalidArgsException as e:
        return error_response(400, f"Invalid arguments: {str(e)}")
    
    except Exception as e:
        print(f"Error issuing certificate: {str(e)}")
        return error_response(500, f"Internal error: {str(e)}")


def error_response(status_code, message):
    """Return a formatted error response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps({
            'error': message
        })
    }

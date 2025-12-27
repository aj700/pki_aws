"""
Lambda function to retrieve Root CA certificate from S3.
"""

import json
import boto3
import os

s3 = boto3.client('s3')

ROOT_CA_BUCKET = os.environ.get('ROOT_CA_BUCKET')


def lambda_handler(event, context):
    """
    Return the Root CA certificate.
    
    Returns:
    - PEM-encoded Root CA certificate
    """
    
    try:
        response = s3.get_object(
            Bucket=ROOT_CA_BUCKET,
            Key='rootCA.crt'
        )
        
        root_cert = response['Body'].read().decode('utf-8')
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/x-pem-file',
                'Content-Disposition': 'attachment; filename="rootCA.crt"'
            },
            'body': root_cert
        }
        
    except s3.exceptions.NoSuchKey:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Root CA certificate not found. Please upload it to S3.'})
        }
        
    except Exception as e:
        print(f"Error retrieving Root CA: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': f'Internal error: {str(e)}'})
        }

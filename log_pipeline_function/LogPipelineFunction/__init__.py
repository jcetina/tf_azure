import json
import logging
import os

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobClient

def main(msg: func.ServiceBusMessage):
    credential = DefaultAzureCredential()
    msg_body = msg.get_body().decode('utf-8')
    msg_dict = json.loads(msg_body)
    blob_url = msg_dict.get('data', {}).get('url')
    logging.info('blob url: {}'.format(blob_url))
    blob_client = BlobClient.from_blob_url(blob_url, credential=credential)
    blob_data = blob_client.download_blob().readall()
    logging.info('blob data: {}'.format(blob_data))
    secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('HEC_VAULT_URI')
    secret_client = SecretClient(vault_url=vault, credential=credential)
    secret = secret_client.get_secret(secret_name)
    logging.info('secret name:{}, secret value:{}'.format(secret.name, secret.value))

import json
import logging
import os

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient


def main(msg: func.ServiceBusMessage):
    msg_body = msg.get_body().decode('utf-8')
    msg_dict = json.loads(msg_body)
    blob_url = msg_dict.get('data', {}).get('url')
    logging.info('blob url: {}'.format(blob_url))
    secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('HEC_VAULT_URI')
    credential = DefaultAzureCredential()
    secret_client = SecretClient(vault_url=vault, credential=credential)
    secret = secret_client.get_secret(secret_name)
    logging.info('secret name:{}, secret value:{}'.format(secret.name, secret.value))
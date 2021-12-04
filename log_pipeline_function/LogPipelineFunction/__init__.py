import logging
import os

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient


def main(msg: func.ServiceBusMessage):
    logging.info('msg body: %s',
                msg.get_body().decode('utf-8'))
    secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('HEC_VAULT_URI')
    credential = DefaultAzureCredential()
    secret_client = SecretClient(vault_url=vault, credential=credential)
    secret = secret_client.get_secret(secret_name)
    logging.info('secret name:{}, secret value:{}'.format(secret.name, secret.value))
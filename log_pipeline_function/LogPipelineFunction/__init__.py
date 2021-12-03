import logging
import os

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import  SecretClient

def main(msg: func.ServiceBusMessage):
    logging.info('msg body: %s',
                 msg.get_body().decode('utf-8'))
    credential = DefaultAzureCredential()
    logging.info('key name', os.environ['HEC_TOKEN_SECRET_NAME'])
    logging.info('hec uri', os.environ['HEC_VAULT_URI'])

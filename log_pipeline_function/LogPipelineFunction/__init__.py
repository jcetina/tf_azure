import os
import logging

import azure.functions as func


from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

logging.info('on')

def main(msg: func.ServiceBusMessage):
    logging.info('here')
    try:
        #credential = DefaultAzureCredential()
        # secret_client = SecretClient(vault_url="https://my-key-vault.vault.azure.net/", credential=credential)
        # secret = secret_client.get_secret("secret-name")
        logging.info('msg body: %s',
                    msg.get_body().decode('utf-8'))
        logging.info('key name', os.environ['HEC_TOKEN_SECRET_NAME'])
        logging.info('hec uri', os.environ['HEC_VAULT_URI'])
    except Exception as e:
        logging.warning(str(e))

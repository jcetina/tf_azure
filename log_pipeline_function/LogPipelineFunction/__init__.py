import os
import logging

import azure.functions as func



def main(msg: func.ServiceBusMessage):
    #credential = DefaultAzureCredential()
    # secret_client = SecretClient(vault_url="https://my-key-vault.vault.azure.net/", credential=credential)
    # secret = secret_client.get_secret("secret-name")
    logging.info('msg body: %s',
                msg.get_body().decode('utf-8'))

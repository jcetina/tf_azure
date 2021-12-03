import logging
import os

import azure.functions as func

logging.info('starting')
try:
    from azure.identity import DefaultAzureCredential
except ImportError as ie:
    logging.info("import error: {}".format(str(ie)))
except Exception as e:
    logging.info("other error: {}".format(str(e)))

# from azure.keyvault.secrets import SecretClient


def main(msg: func.ServiceBusMessage):
    try:
        logging.info(DefaultAzureCredential)
    except Exception as e:
        logging.info("DefaultAzureCredential error: {}".format(str(e)))
    logging.info('msg body: %s',
                msg.get_body().decode('utf-8'))
    secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('HEC_VAULT_URI')
    s2 = """
    try:
        credential = DefaultAzureCredential()
        secret_client = SecretClient(vault_url=vault, credential=credential)
        secret = secret_client.get_secret(secret_name)
        logging.info('{}: {}'.format(secret_name, secret))
    except Exception as e:
        logging.info(str(e))
    """
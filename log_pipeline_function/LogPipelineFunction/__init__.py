import logging
import os

import azure.functions as func

def main():
    logging.info(str(os.environ))
    foo = """
    def main(msg: func.ServiceBusMessage):
        logging.info('msg body: %s',
                    msg.get_body().decode('utf-8'))
        logging.info('hec_name {}'.format(os.environ.get('HEC_TOKEN_SECRET_NAME')))
        logging.info('vault_uri {}'.format(os.environ.get('HEC_VAULT_URI')))
        logging.info(str(os.environ))
    """
import logging

import azure.functions as func


def main(msg: func.ServiceBusMessage):
    logging.info('msg body thonk: %s',
                 msg.get_body().decode('utf-8'))

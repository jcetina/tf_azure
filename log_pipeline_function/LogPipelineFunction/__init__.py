import logging

import azure.functions as func


def main(msg: func.ServiceBusMessage):
    logging.info('OMGWTFBBQ: %s',
                 msg.get_body().decode('utf-8'))

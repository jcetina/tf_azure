import logging

import azure.functions as func


def main(msg: func.ServiceBusMessage):
    logging.info('msg body asdf nba bbq: %s',
                 msg.get_body().decode('utf-8'))

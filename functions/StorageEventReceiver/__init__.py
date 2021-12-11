import io
import json
import logging

import azure.functions as func
import typing

from avro.datafile import DataFileReader
from avro.io import DatumReader
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobClient

class File(io.BytesIO):
    # need to make a fake file object with a mode attribute for avro file reader. Dumb.
    def __init__(self):
        self.mode = 'b'

def get_blob(blob_url, credentials):
    logging.info('Getting blob url: {}'.format(blob_url))
    blob_file = File()
    logging.info('blob url: {}'.format(blob_url))
    blob_client = BlobClient.from_blob_url(blob_url, credential=credentials)
    blob_stream = blob_client.download_blob()
    _ = blob_stream.download_to_stream(blob_file) #r eturns BlobProperties
    blob_file.seek(0)

def gather_audit_records(blob_file):
    reader = DataFileReader(blob_file, DatumReader())
    output_records = []
    for row in reader:
        body = row['Body']
        if body:
            body = body.decode('utf-8')
        else:
            return
        d = json.loads(body)
        records = d['records']
        for record in records:
            record_json = json.dumps(record)
            output_records.append(record_json)
    return output_records

def main(msg: func.ServiceBusMessage, output: func.Out[typing.List[str]]):
    try:
        credentials = DefaultAzureCredential()
        msg_body = msg.get_body().decode('utf-8')
        msg_dict = json.loads(msg_body)
        blob_url = msg_dict.get('data', {}).get('url')
        blob_file = get_blob(blob_url, credentials)
    except Exception as e:
        # Error handling strategy: log the error and raise it again.
        # This will cause the function app to return non-0, which will
        # leave the message in the service bus queue. If it doesn't work 5 times,
        # it will dead letter, which is what we want.
        logging.error('Error retrieving blob: {}'.format(str(e)))
        raise

    try:
        output_records = gather_audit_records(blob_file)
    except Exception as e:
        # same error handling strategy
        logging.error('Error retrieving output records: {}'.format(str(e)))
        raise

    try:
        output.set(output_records)
    except Exception as e:
        # same error handling strategy
        logging.error('Error publishing output to queue: {}'.format(str(e)))
        raise
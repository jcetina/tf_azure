import io
import json
import logging
import os

import azure.functions as func
import requests

from avro.datafile import DataFileReader
from avro.io import DatumReader, BinaryDecoder
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobClient
from opencensus.ext.azure import metrics_exporter
from opencensus.stats import aggregation as aggregation_module
from opencensus.stats import measure as measure_module
from opencensus.stats import stats as stats_module
from opencensus.stats import view as view_module
from opencensus.tags import tag_map as tag_map_module

class File(io.BytesIO):
    # need to make a fake file object with a mode attribute for avro file reader. Dumb.
    def __init__(self):
        super().__init__()
        self.mode = 'b'

def main(msg: func.ServiceBusMessage, output: func.Out[bytes]):
    

    blob_data = File()
    credential = DefaultAzureCredential()
    msg_body = msg.get_body().decode('utf-8')
    msg_dict = json.loads(msg_body)
    blob_url = msg_dict.get('data', {}).get('url')
    logging.info('blob url: {}'.format(blob_url))
    blob_client = BlobClient.from_blob_url(blob_url, credential=credential)
    blob_stream = blob_client.download_blob()
    blob_byte_count = blob_stream.download_to_stream(blob_data)
    blob_data.seek(0)
    #logging.info('blob data: {}'.format(blob_data))
    hec_secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('VAULT_URI')
    secret_client = SecretClient(vault_url=vault, credential=credential)
    hec_secret = secret_client.get_secret(hec_secret_name)
    logging.info('secret name:{}, secret value:{}'.format(hec_secret.name, 'redacted'))
    decoder = BinaryDecoder(blob_data)
    reader = DatumReader()
    hec_event_string = ''
    line_count = 0
    queue_output = []
    for record in reader:
        line = json.dumps(record)
        hec_event_string += '{}\n'.format(line)
        queue_output.append(line.encode('utf-8'))
        line_count += 1
    
    output.set(queue_output)

    # opencensus foo
    try:
        stats = stats_module.stats
        view_manager = stats.view_manager
        stats_recorder = stats.stats_recorder
        
        LINES_MEASURE = measure_module.MeasureInt("line_count", "Number of lines in received file", "1")
        BYTES_MEASURE = measure_module.MeasureInt("byte_count", "Number of bytes in received file", "By")

        LINES_VIEW = view_module.View('lines_view', "number of lines", [], LINES_MEASURE, aggregation_module.SumAggregation())
        BYTES_VIEW = view_module.View('bytes_view', "number of bytes", [], BYTES_MEASURE, aggregation_module.SumAggregation())

        connection_string = 'InstrumentationKey={}'.format(os.environ['APPINSIGHTS_INSTRUMENTATIONKEY'])
        exporter = metrics_exporter.new_metrics_exporter(
            connection_string=connection_string
        )
        view_manager.register_exporter(exporter)
        view_manager.register_view(LINES_VIEW)
        view_manager.register_view(BYTES_VIEW)
        mmap = stats_recorder.new_measurement_map()
        tmap = tag_map_module.TagMap()

        mmap.measure_int_put(LINES_MEASURE, line_count)
        mmap.measure_int_put(BYTES_MEASURE, blob_byte_count)
        mmap.record(tmap)
        logging.info('lines: {}, bytes: {}'.format(line_count, blob_byte_count))

        url='https://splunk.mattuebel.com/services/collector/raw?channel=49b42560-9fde-40f6-8c9b-32e0d81be1e2&sourcetype=test'
        authHeader = {'Authorization': 'Splunk {}'.format(hec_secret.value)}

        r = requests.post(url, headers=authHeader, data=hec_event_string.encode('utf-8'), verify=False)
        logging.info('response: {}'.format(r.text))

    except Exception as e:
        logging.info('error: {}'.format(str(e)))
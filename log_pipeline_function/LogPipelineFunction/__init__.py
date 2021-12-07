import json
import logging
import os

import azure.functions as func

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.storage.blob import BlobClient
from opencensus.ext.azure import metrics_exporter
from opencensus.stats import aggregation as aggregation_module, view
from opencensus.stats import measure as measure_module
from opencensus.stats import stats as stats_module
from opencensus.stats import view as view_module
from opencensus.tags import tag_map as tag_map_module



def main(msg: func.ServiceBusMessage):
    

    credential = DefaultAzureCredential()
    msg_body = msg.get_body().decode('utf-8')
    msg_dict = json.loads(msg_body)
    blob_url = msg_dict.get('data', {}).get('url')
    logging.info('blob url: {}'.format(blob_url))
    blob_client = BlobClient.from_blob_url(blob_url, credential=credential)
    blob_data = blob_client.download_blob().readall()
    logging.info('blob data: {}'.format(blob_data))
    secret_name = os.environ.get('HEC_TOKEN_SECRET_NAME')
    vault = os.environ.get('HEC_VAULT_URI')
    secret_client = SecretClient(vault_url=vault, credential=credential)
    secret = secret_client.get_secret(secret_name)
    logging.info('secret name:{}, secret value:{}'.format(secret.name, secret.value))

    # opencensus foo
    stats = stats_module.stats
    view_manager = stats.view_manager
    stats_recorder = stats.stats_recorder
    
    LINES_MEASURE = measure_module.MeasureInt("line_count", "Number of lines in received file", "1")
    BYTES_MEASURE = measure_module.MeasureInt("line_count", "Number of bytes in received file", "By")

    LINES_VIEW = view_module.View('lines_view', "number of lines", [], LINES_MEASURE, aggregation_module.CountAggregation())
    BYTES_VIEW = view_module.View('bytes_view', "number of lines", [], BYTES_MEASURE, aggregation_module.CountAggregation())

    exporter = metrics_exporter.new_metrics_exporter(connection_string=os.environ['APPINSIGHTS_INSTRUMENTATIONKEY'])
    view_manager.register_exporter(exporter)
    view_manager.register_view(LINES_VIEW)
    view_manager.register_view(BYTES_VIEW)
    mmap = stats_recorder.new_measurement_map()
    tmap = tag_map_module.TagMap()

    mmap.measure_int_put(LINES_MEASURE, len(blob_data.decode('utf-8').splitlines()))
    mmap.measure_int_put(BYTES_MEASURE, len(blob_data))
    mmap.record(tmap)

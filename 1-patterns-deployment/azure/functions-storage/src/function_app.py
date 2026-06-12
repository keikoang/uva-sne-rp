import logging
import os

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


@app.route(route="StorageHealth", methods=["GET"])
def storage_health(req: func.HttpRequest) -> func.HttpResponse:
    account_name = os.environ['STORAGE_ACCOUNT_NAME']
    container_name = os.environ['STORAGE_CONTAINER_NAME']
    key = 'test.txt'

    logging.info(f"Reading https://{account_name}.blob.core.windows.net/{container_name}/{key}")

    client = BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net",
        credential=DefaultAzureCredential()
    )

    try:
        raw = client.get_blob_client(container=container_name, blob=key).download_blob().readall()

        try:
            body = raw.decode('utf-8')
        except UnicodeDecodeError:
            body = raw.decode('utf-16')

        logging.info("Read succeeded")
        return func.HttpResponse(body, status_code=200)

    except Exception:
        logging.exception("Blob read failed")
        raise

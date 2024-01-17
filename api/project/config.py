import os


basedir = os.path.abspath(os.path.dirname(__file__))


class Config(object):
    ARKIME_FIELDS_INDEX = f"{os.getenv('ARKIME_FIELDS_INDEX', 'arkime_fields')}"
    MALCOLM_NETWORK_INDEX_PATTERN = f"{os.getenv('MALCOLM_NETWORK_INDEX_PATTERN', 'arkime_sessions3-*')}"
    MALCOLM_NETWORK_INDEX_TIME_FIELD = f"{os.getenv('MALCOLM_NETWORK_INDEX_TIME_FIELD', 'firstPacket')}"
    MALCOLM_OTHER_INDEX_PATTERN = f"{os.getenv('MALCOLM_OTHER_INDEX_PATTERN', 'malcolm_beats_*')}"
    MALCOLM_OTHER_INDEX_TIME_FIELD = f"{os.getenv('MALCOLM_OTHER_INDEX_TIME_FIELD', '@timestamp')}"
    ARKIME_NETWORK_INDEX_PATTERN = f"{os.getenv('ARKIME_NETWORK_INDEX_PATTERN', 'arkime_sessions3-*')}"
    ARKIME_NETWORK_INDEX_TIME_FIELD = f"{os.getenv('ARKIME_NETWORK_INDEX_TIME_FIELD', 'firstPacket')}"

    DOCTYPE_DEFAULT = f"{os.getenv('DOCTYPE_DEFAULT', 'network')}"
    BUILD_DATE = f"{os.getenv('BUILD_DATE', 'unknown')}"
    DASHBOARDS_URL = f"{os.getenv('DASHBOARDS_URL', 'http://dashboards:5601/dashboards')}"
    MALCOLM_API_PREFIX = f"{os.getenv('MALCOLM_API_PREFIX', 'mapi')}"
    MALCOLM_API_DEBUG = f"{os.getenv('MALCOLM_API_DEBUG', 'false')}"
    MALCOLM_TEMPLATE = f"{os.getenv('MALCOLM_TEMPLATE', 'malcolm_template')}"
    MALCOLM_VERSION = f"{os.getenv('MALCOLM_VERSION', 'unknown')}"
    OPENSEARCH_URL = f"{os.getenv('OPENSEARCH_URL', 'http://opensearch:9200')}"
    OPENSEARCH_PRIMARY = f"{os.getenv('OPENSEARCH_PRIMARY', 'opensearch-local')}"
    OPENSEARCH_SSL_CERTIFICATE_VERIFICATION = f"{os.getenv('OPENSEARCH_SSL_CERTIFICATE_VERIFICATION', 'false')}"
    OPENSEARCH_CREDS_CONFIG_FILE = (
        f"{os.getenv('OPENSEARCH_CREDS_CONFIG_FILE', '/var/local/curlrc/.opensearch.primary.curlrc')}"
    )
    RESULT_SET_LIMIT = int(f"{os.getenv('RESULT_SET_LIMIT', '500')}")
    VCS_REVISION = f"{os.getenv('VCS_REVISION', 'unknown')}"

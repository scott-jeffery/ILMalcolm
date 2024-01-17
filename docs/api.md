# <a name="API"></a>API

* [Field Aggregations](api-aggregations.md)
* [Document Lookup](api-document-lookup.md)
* [Event Logging](api-event-logging.md)
* [Fields](api-fields.md)
* [Indices](api-indices.md)
* [Ping](api-ping.md)
* [Version](api-version.md)
* [Examples](api-examples.md)

Malcolm provides a [REST API]({{ site.github.repository_url }}/blob/{{ site.github.build_revision }}/api/project/__init__.py) that can be used to programatically query some aspects of Malcolm's status and data.

In addition to the items listed above, Malcolm will also forward requests to some of its components' APIs at the following URIs:

* **/mapi/logstash/** - the [Logstash `/_node/stats/` API](https://www.elastic.co/guide/en/logstash/current/node-stats-api.html)
* **/mapi/opensearch/** - the [OpenSearch API](https://opensearch.org/docs/latest/api-reference/)
* **/mapi/netbox/** - the [NetBox API](https://demo.netbox.dev/static/docs/rest-api/overview/) (also accessible at `/netbox/api/`)
* **/arkime/api/** - the [Arkime Viewer API](https://arkime.com/apiv3)

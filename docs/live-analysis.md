# <a name="LiveAnalysis"></a>Live analysis

* [Live analysis](#LiveAnalysis)
    - [Using a network sensor appliance](#Hedgehog)
    - [Monitoring local network interfaces](#LocalPCAP)
        + ["Hedgehog" run profile](#Profiles)
    - [Manually forwarding logs from an external source](#ExternalForward)

## <a name="Hedgehog"></a>Using a network sensor appliance

A dedicated network sensor appliance is the recommended method for capturing and analyzing live network traffic when performance and throughput is of utmost importance. [Hedgehog Linux](hedgehog.md) is a custom Debian-based operating system built to:

* monitor network interfaces
* capture packets to PCAP files
* detect file transfers in network traffic and extract and scan those files for threats
* generate and forward Zeek and Suricata logs, Arkime sessions, and other information to [Malcolm]({{ site.github.repository_url }})

Please see the [Hedgehog Linux README](hedgehog.md) for more information.

## <a name="LocalPCAP"></a>Monitoring local network interfaces

The options for monitoring traffic on local network interfaces can be [configured](malcolm-hedgehog-e2e-iso-install.md#MalcolmConfig) by running [`./scripts/configure`](malcolm-config.md#ConfigAndTuning).

Malcolm's `pcap-capture`, `suricata-live` and `zeek-live` containers can monitor one or more local network interfaces, specified by the `PCAP_IFACE` environment variable in [`pcap-capture.env`](malcolm-config.md#MalcolmConfigEnvVars). These containers are started with additional privileges to allow opening network interfaces in promiscuous mode for capture.

The instances of Zeek and Suricata (in the `suricata-live` and `zeek-live` containers when the `SURICATA_LIVE_CAPTURE` and `ZEEK_LIVE_CAPTURE` [environment variables](malcolm-config.md#MalcolmConfigEnvVars) are set to `true`, respectively) analyze traffic on-the-fly and generate log files containing network session metadata. These log files are in turn scanned by [Filebeat](https://www.elastic.co/products/beats/filebeat) and forwarded to [Logstash](https://www.elastic.co/products/logstash) for enrichment and indexing into the [OpenSearch](https://opensearch.org/) document store.

In contrast, the `pcap-capture` container buffers traffic to PCAP files and periodically rotates these files for processing (by Arkime's `capture` utlity in the `arkime` container) according to the thresholds defined by the `PCAP_ROTATE_MEGABYTES` and `PCAP_ROTATE_MINUTES` environment variables in [`pcap-capture.env`](malcolm-config.md#MalcolmConfigEnvVars). If for some reason (e.g., a low resources environment) you also want Zeek and Suricata to process these intermediate PCAP files rather than monitoring the network interfaces directly, you can set `SURICATA_ROTATED_PCAP`/`ZEEK_ROTATED_PCAP` to `true` and `SURICATA_LIVE_CAPTURE`/`ZEEK_LIVE_CAPTURE` to false. The only exception to this behavior (i.e., the creation of intermediate PCAP files by `netsniff-ng` or `tcpdump` in the `pcap-capture` which are periodically rolled over for processing by Arkime) is when running the ["Hedgehog" run profile](#Profiles) or when using [a remote OpenSearch or Elasticsearch instance](opensearch-instances.md#OpenSearchInstance). In either of these configurations, users may choose to have Arkime's `capture` tool monitor live traffic on the network interface without using the intermediate PCAP file.

Note that Microsoft Windows and Apple macOS platforms currently run Docker inside of a virtualized environment. Live traffic capture and analysis on those platforms would require additional configuration of virtual interfaces and port forwarding in Docker, which is outside of the scope of this document.

### <a name="Profiles"></a>"Hedgehog" run profile

Another configuration for monitoring local network interfaces is to use the `hedgehog` run profile. During [Malcolm configuration](malcolm-hedgehog-e2e-iso-install.md#MalcolmConfig) users are prompted "**Run with Malcolm (all containers) or Hedgehog (capture only) profile?**" Docker Compose can use [profiles](https://docs.docker.com/compose/profiles/) to selectively start services. While the `malcolm` run profile runs all of Malcolm's containers (OpenSearch, Dashboards, LogStash, etc.), the `hedgehog` profile runs *only* the containers necessary for traffic capture.

When configuring the `hedgehog` profile, users must provide connection details for another Malcolm instance to which to forward its network traffic logs.

## <a name="ExternalForward"></a>Manually forwarding logs from an external source

Malcolm's Logstash instance can also be configured to accept logs from a [remote forwarder](https://www.elastic.co/products/beats/filebeat) by running [`./scripts/configure`](malcolm-config.md#ConfigAndTuning) and answering "yes" to "`Expose Logstash port to external hosts?`" Enabling encrypted transport of these log files is discussed in [Configure authentication](authsetup.md#AuthSetup) and the description of the `BEATS_SSL` environment variable in [`beats-common.env`](malcolm-config.md#MalcolmConfigEnvVars).

Configuring Filebeat to forward Zeek logs to Malcolm might look something like this example [`filebeat.yml`](https://www.elastic.co/guide/en/beats/filebeat/current/filebeat-reference-yml.html):
```
filebeat.inputs:
- type: log
  paths:
    - /var/zeek/*.log
  fields_under_root: true
  compression_level: 0
  exclude_lines: ['^\s*#']
  scan_frequency: 10s
  clean_inactive: 180m
  ignore_older: 120m
  close_inactive: 90m
  close_renamed: true
  close_removed: true
  close_eof: false
  clean_renamed: true
  clean_removed: true

output.logstash:
  hosts: ["192.0.2.123:5044"]
  ssl.enabled: true
  ssl.certificate_authorities: ["/foo/bar/ca.crt"]
  ssl.certificate: "/foo/bar/client.crt"
  ssl.key: "/foo/bar/client.key"
  ssl.supported_protocols: "TLSv1.2"
  ssl.verification_mode: "none"
```
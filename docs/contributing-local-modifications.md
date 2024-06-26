# <a name="LocalMods"></a>Local modifications

There are several ways to customize Malcolm's runtime behavior via local changes to configuration files. Many commonly-tweaked settings are discussed in the project [README](README.md) (see [Environment Variable Files](malcolm-config.md#MalcolmConfigEnvVars) and [Customizing event severity scoring](severity.md#SeverityConfig) for some examples).

## <a name="Bind"></a>Docker bind mounts

Some configuration changes can be put in place by modifying local copies of configuration files and then using a [Docker bind mount](https://docs.docker.com/storage/bind-mounts/) to overlay the modified file onto the running Malcolm container. This is already done for many files and directories used to persist Malcolm configuration and data. For example, the default list of bind mounted files and directories for each Malcolm service is as follows:

```
$ grep -P "^(      - ./|  [\w-]+:)" docker-compose.yml
opensearch:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./.opensearch.secondary.curlrc:/var/local/curlrc/.opensearch.secondary.curlrc:ro
    - ./opensearch:/usr/share/opensearch/data
    - ./opensearch-backup:/opt/opensearch/backup
    - ./opensearch/opensearch.keystore:/usr/share/opensearch/config/persist/opensearch.keystore:rw
dashboards-helper:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./.opensearch.secondary.curlrc:/var/local/curlrc/.opensearch.secondary.curlrc:ro
dashboards:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
logstash:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./.opensearch.secondary.curlrc:/var/local/curlrc/.opensearch.secondary.curlrc:ro
    - ./logstash/maps/malcolm_severity.yaml:/etc/malcolm_severity.yaml:ro
    - ./logstash/certs/ca.crt:/certs/ca.crt:ro
    - ./logstash/certs/server.crt:/certs/server.crt:ro
    - ./logstash/certs/server.key:/certs/server.key:ro
filebeat:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./zeek-logs:/zeek
    - ./suricata-logs:/suricata
    - ./filebeat/certs/ca.crt:/certs/ca.crt:ro
    - ./filebeat/certs/client.crt:/certs/client.crt:ro
    - ./filebeat/certs/client.key:/certs/client.key:ro
arkime:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./pcap:/data/pcap
zeek:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./pcap:/pcap
    - ./zeek-logs/upload:/zeek/upload
    - ./zeek-logs/extract_files:/zeek/extract_files
    - ./zeek/intel:/opt/zeek/share/zeek/site/intel
    - ./zeek/custom:/opt/zeek/share/zeek/site/custom:ro
zeek-live:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./zeek-logs/live:/zeek/live
    - ./zeek-logs/extract_files:/zeek/extract_files
    - ./zeek/intel:/opt/zeek/share/zeek/site/intel
    - ./zeek/custom:/opt/zeek/share/zeek/site/custom:ro
suricata:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./suricata-logs:/var/log/suricata
    - ./pcap:/data/pcap
    - ./suricata/rules:/opt/suricata/rules:ro
    - ./suricata/include-configs:/opt/suricata/include-configs:ro
suricata-live:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./suricata-logs:/var/log/suricata
    - ./suricata/rules:/opt/suricata/rules:ro
    - ./suricata/include-configs:/opt/suricata/include-configs:ro
file-monitor:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./zeek-logs/extract_files:/zeek/extract_files
    - ./zeek-logs/current:/zeek/logs
    - ./yara/rules:/yara-rules/custom:ro
pcap-capture:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./pcap/upload:/pcap
pcap-monitor:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
    - ./zeek-logs:/zeek
    - ./pcap:/pcap
upload:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./pcap/upload:/var/www/upload/server/php/chroot/files
htadmin:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./htadmin/config.ini:/var/www/htadmin/config/config.ini:rw
    - ./htadmin/metadata:/var/www/htadmin/config/metadata:rw
    - ./nginx/htpasswd:/var/www/htadmin/auth/htpasswd:rw
freq:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
netbox:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./netbox/config:/etc/netbox/config:ro
    - ./netbox/media:/opt/netbox/netbox/media:rw
    - ./net-map.json:/usr/local/share/net-map.json:ro
netbox-postgres:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./netbox/postgres:/var/lib/postgresql/data:rw
netbox-redis:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./netbox/redis:/data
netbox-redis-cache:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
api:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./.opensearch.primary.curlrc:/var/local/curlrc/.opensearch.primary.curlrc:ro
nginx-proxy:
    - ./nginx/ca-trust:/var/local/ca-trust:ro
    - ./nginx/nginx_ldap.conf:/etc/nginx/nginx_ldap.conf:ro
    - ./nginx/htpasswd:/etc/nginx/auth/htpasswd:ro
    - ./nginx/certs:/etc/nginx/certs:ro
    - ./nginx/certs/dhparam.pem:/etc/nginx/dhparam/dhparam.pem:ro
```

So, for example, if a user wanted to make a change to the `nginx-proxy` container's `nginx.conf` file, they could add the following line to the `volumes:` section of the `nginx-proxy` service in the `docker-compose.yml` file:

```
- ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
```

The change would take effect after stopping and starting Malcolm.

See the documentation on [Docker bind mount](https://docs.docker.com/storage/bind-mounts/) for more information on this technique.

## <a name="ContribBuild"></a>Building Malcolm's Docker images

Another method for modifying local copies of Malcolm's services' containers is to [build custom](development.md#Build) containers with the modifications baked-in.

For example, imagine a user wanted to create a Malcolm container that includes a new dashboard for OpenSearch Dashboards and a new enrichment filter `.conf` file for Logstash. After placing these files under `./dashboards/dashboards` and `./logstash/pipelines/enrichment`, respectively, in the Malcolm working copy, run `./build.sh dashboards-helper logstash` to build just those containers. After the build completes, run `docker images` to see the fresh images for `ghcr.io/idaholab/malcolm/dashboards-helper` and `ghcr.io/idaholab/malcolm/logstash-oss`. Users may need to review the contents of the [Dockerfiles]({{ site.github.repository_url }}/blob/{{ site.github.build_revision }}/Dockerfiles) to determine the correct service and filesystem location within that service's Docker image depending on the nature of the task.

Alternately, forks of Malcolm on GitHub contain [workflow files]({{ site.github.repository_url }}/tree/{{ site.github.build_revision }}/.github/workflows/) that contain instructions for GitHub to build the docker images and [sensor](live-analysis.md#Hedgehog) and [Malcolm](malcolm-iso.md#ISO) installer ISOs. The resulting images are named according to the pattern `ghcr.io/owner/malcolm/image:branch` (e.g., if the GitHub user `romeogdetlevjr` has forked Malcolm, the `arkime` container built for the `main` branch would be named `ghcr.io/romeogdetlevjr/malcolm/arkime:main`). To run a local instance of Malcolm using these images instead of the official ones, users would need to edit their `docker-compose.yml` file(s) and replace the `image:` tags according to this new pattern, or use the bash helper script `./shared/bin/github_image_helper.sh` to pull and re-tag the images.
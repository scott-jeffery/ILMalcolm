#!/bin/bash

# Copyright (c) 2023 Battelle Energy Alliance, LLC.  All rights reserved.

set -euo pipefail
shopt -s nocasematch

DASHB_URL=${DASHBOARDS_URL:-"http://dashboards:5601/dashboards"}
INDEX_PATTERN=${ARKIME_INDEX_PATTERN:-"arkime_sessions3-*"}
INDEX_PATTERN_ID=${ARKIME_INDEX_PATTERN_ID:-"arkime_sessions3-*"}
INDEX_TIME_FIELD=${ARKIME_INDEX_TIME_FIELD:-"firstPacket"}
DUMMY_DETECTOR_NAME=${DUMMY_DETECTOR_NAME:-"malcolm_init_dummy"}
DARK_MODE=${DASHBOARDS_DARKMODE:-"true"}

MALCOLM_TEMPLATES_DIR="/opt/templates"
MALCOLM_TEMPLATE_FILE_ORIG="$MALCOLM_TEMPLATES_DIR/malcolm_template.json"
MALCOLM_TEMPLATE_FILE="/data/init/malcolm_template.json"
DEFAULT_DASHBOARD=${OPENSEARCH_DEFAULT_DASHBOARD:-"0ad3d7c2-3441-485e-9dfe-dbb22e84e576"}

ISM_SNAPSHOT_REPO=${ISM_SNAPSHOT_REPO:-"logs"}
ISM_SNAPSHOT_COMPRESSED=${ISM_SNAPSHOT_COMPRESSED:-"false"}

OPENSEARCH_PRIMARY=${OPENSEARCH_PRIMARY:-"opensearch-local"}
OPENSEARCH_SECONDARY=${OPENSEARCH_SECONDARY:-""}

# is the argument to automatically create this index enabled?
if [[ "$CREATE_OS_ARKIME_SESSION_INDEX" = "true" ]] ; then

  # give OpenSearch time to start and Arkime to get its template created before configuring dashboards
  /data/opensearch_status.sh -l arkime_sessions3_template >/dev/null 2>&1

  for LOOP in primary secondary; do

    if [[ "$LOOP" == "primary" ]]; then
      OPENSEARCH_URL_TO_USE=${OPENSEARCH_URL:-"http://opensearch:9200"}
      OPENSEARCH_CREDS_CONFIG_FILE_TO_USE=${OPENSEARCH_CREDS_CONFIG_FILE:-"/var/local/curlrc/.opensearch.primary.curlrc"}
      if ( [[ "$OPENSEARCH_PRIMARY" == "opensearch-remote" ]] || [[ "$OPENSEARCH_PRIMARY" == "elasticsearch-remote" ]] ) && [[ -r "$OPENSEARCH_CREDS_CONFIG_FILE_TO_USE" ]]; then
        OPENSEARCH_LOCAL=false
        CURL_CONFIG_PARAMS=(
          --config
          "$OPENSEARCH_CREDS_CONFIG_FILE_TO_USE"
          )
      else
        OPENSEARCH_LOCAL=true
        CURL_CONFIG_PARAMS=()

      fi
      DATASTORE_TYPE="$(echo "$OPENSEARCH_PRIMARY" | cut -d- -f1)"

    elif [[ "$LOOP" == "secondary" ]] && ( [[ "$OPENSEARCH_SECONDARY" == "opensearch-remote" ]] || [[ "$OPENSEARCH_SECONDARY" == "elasticsearch-remote" ]] ) && [[ -n "${OPENSEARCH_SECONDARY_URL:-""}" ]]; then
      OPENSEARCH_URL_TO_USE=$OPENSEARCH_SECONDARY_URL
      OPENSEARCH_LOCAL=false
      OPENSEARCH_CREDS_CONFIG_FILE_TO_USE=${OPENSEARCH_SECONDARY_CREDS_CONFIG_FILE:-"/var/local/curlrc/.opensearch.secondary.curlrc"}
      if [[ -r "$OPENSEARCH_CREDS_CONFIG_FILE_TO_USE" ]]; then
        CURL_CONFIG_PARAMS=(
          --config
          "$OPENSEARCH_CREDS_CONFIG_FILE_TO_USE"
          )
      else
        CURL_CONFIG_PARAMS=()
      fi
      DATASTORE_TYPE="$(echo "$OPENSEARCH_SECONDARY" | cut -d- -f1)"

    else
      continue
    fi
    [[ -z "$DATASTORE_TYPE" ]] && DATASTORE_TYPE="opensearch"
    if [[ "$DATASTORE_TYPE" == "elasticsearch" ]]; then
      DASHBOARDS_URI_PATH="kibana"
      XSRF_HEADER="kbn-xsrf"
      ECS_TEMPLATES_DIR=/opt/ecs-templates
    else
      DASHBOARDS_URI_PATH="opensearch-dashboards"
      XSRF_HEADER="osd-xsrf"
      ECS_TEMPLATES_DIR=/opt/ecs-templates-os
    fi

    # is the Dashboards process server up and responding to requests?
    if [[ "$LOOP" != "primary" ]] || curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --fail -XGET "$DASHB_URL/api/status" ; then

      # have we not not already created the index pattern?
      if [[ "$LOOP" != "primary" ]] || ! curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --fail -XGET "$DASHB_URL/api/saved_objects/index-pattern/$INDEX_PATTERN_ID" ; then

        echo "$DATASTORE_TYPE ($LOOP) is running at \"${OPENSEARCH_URL_TO_USE}\"!"

        # register the repo name/path for opensearch snapshots (but don't count this an unrecoverable failure)
        if [[ "$LOOP" == "primary" ]] && [[ "$OPENSEARCH_LOCAL" == "true" ]]; then
          echo "Registering index snapshot repository..."
          curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -H "Accept: application/json" \
            -H "Content-type: application/json" \
            -XPUT -fsSL "$OPENSEARCH_URL_TO_USE/_snapshot/$ISM_SNAPSHOT_REPO" \
            -d "{ \"type\": \"fs\", \"settings\": { \"location\": \"$ISM_SNAPSHOT_REPO\", \"compress\": $ISM_SNAPSHOT_COMPRESSED } }" \
            || true
        fi

        # calculate combined SHA sum of all templates to save as _meta.hash to determine if
        # we need to do this import (mostly useful for the secondary loop)
        TEMPLATE_HASH="$(find "$ECS_TEMPLATES_DIR"/composable "$MALCOLM_TEMPLATES_DIR" -type f -name "*.json" -size +2c 2>/dev/null | sort | xargs -r cat | sha256sum | awk '{print $1}')"

        # get the previous stored template hash (if any) to avoid importing if it's already been imported
        set +e
        TEMPLATE_HASH_OLD="$(curl "${CURL_CONFIG_PARAMS[@]}" -sSL --fail -XGET -H "Content-Type: application/json" "$OPENSEARCH_URL_TO_USE/_index_template/malcolm_template" 2>/dev/null | jq --raw-output '.index_templates[]|select(.name=="malcolm_template")|.index_template._meta.hash' 2>/dev/null)"
        set -e

        # information about other index patterns will be obtained during template import
        OTHER_INDEX_PATTERNS=()

        # proceed only if the current template HASH doesn't match the previously imported one, or if there
        # was an error calculating or storing either
        if [[ "$TEMPLATE_HASH" != "$TEMPLATE_HASH_OLD" ]] || [[ -z "$TEMPLATE_HASH_OLD" ]] || [[ -z "$TEMPLATE_HASH" ]]; then

          if [[ -d "$ECS_TEMPLATES_DIR"/composable/component ]]; then
            echo "Importing ECS composable templates..."
            for i in "$ECS_TEMPLATES_DIR"/composable/component/*.json; do
              TEMP_BASENAME="$(basename "$i")"
              TEMP_FILENAME="${TEMP_BASENAME%.*}"
              echo "Importing ECS composable template $TEMP_FILENAME ..."
              curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" "$OPENSEARCH_URL_TO_USE/_component_template/ecs_$TEMP_FILENAME" -d "@$i" 2>&1 || true
            done
          fi

          if [[ -d "$MALCOLM_TEMPLATES_DIR"/composable/component ]]; then
            echo "Importing custom ECS composable templates..."
            for i in "$MALCOLM_TEMPLATES_DIR"/composable/component/*.json; do
              TEMP_BASENAME="$(basename "$i")"
              TEMP_FILENAME="${TEMP_BASENAME%.*}"
              echo "Importing custom ECS composable template $TEMP_FILENAME ..."
              curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" "$OPENSEARCH_URL_TO_USE/_component_template/custom_$TEMP_FILENAME" -d "@$i" 2>&1 || true
            done
          fi

          echo "Importing malcolm_template ($TEMPLATE_HASH)..."

          if [[ -f "$MALCOLM_TEMPLATE_FILE_ORIG" ]] && [[ ! -f "$MALCOLM_TEMPLATE_FILE" ]]; then
            cp "$MALCOLM_TEMPLATE_FILE_ORIG" "$MALCOLM_TEMPLATE_FILE"
          fi

          # store the TEMPLATE_HASH we calculated earlier as the _meta.hash for the malcolm template
          MALCOLM_TEMPLATE_FILE_TEMP="$(mktemp)"
          ( jq "._meta.hash=\"$TEMPLATE_HASH\"" "$MALCOLM_TEMPLATE_FILE" >"$MALCOLM_TEMPLATE_FILE_TEMP" 2>/dev/null ) && \
            [[ -s "$MALCOLM_TEMPLATE_FILE_TEMP" ]] && \
            cp -f "$MALCOLM_TEMPLATE_FILE_TEMP" "$MALCOLM_TEMPLATE_FILE" && \
            rm -f "$MALCOLM_TEMPLATE_FILE_TEMP"

          # load malcolm_template containing malcolm data source field type mappings (merged from /opt/templates/malcolm_template.json to /data/init/malcolm_template.json in dashboard-helpers on startup)
          curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" \
            "$OPENSEARCH_URL_TO_USE/_index_template/malcolm_template" -d "@$MALCOLM_TEMPLATE_FILE" 2>&1

          # import other templates as well (and get info for creating their index patterns)
          for i in "$MALCOLM_TEMPLATES_DIR"/*.json; do
            TEMP_BASENAME="$(basename "$i")"
            TEMP_FILENAME="${TEMP_BASENAME%.*}"
            if [[ "$TEMP_FILENAME" != "malcolm_template" ]]; then
              echo "Importing template \"$TEMP_FILENAME\"..."
              if curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" "$OPENSEARCH_URL_TO_USE/_index_template/$TEMP_FILENAME" -d "@$i" 2>&1; then
                for TEMPLATE_INDEX_PATTERN in $(jq '.index_patterns[]' "$i" | tr -d '"'); do
                  OTHER_INDEX_PATTERNS+=("$TEMPLATE_INDEX_PATTERN;$TEMPLATE_INDEX_PATTERN;@timestamp")
                done
              fi
            fi
          done

        else
          echo "malcolm_template ($TEMPLATE_HASH) already exists ($LOOP) at \"${OPENSEARCH_URL_TO_USE}\""

        fi # TEMPLATE_HASH check

        if [[ "$LOOP" == "primary" ]]; then
          echo "Importing index pattern..."

          # From https://github.com/elastic/kibana/issues/3709
          # Create index pattern
          curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" -H "$XSRF_HEADER: anything" \
            "$DASHB_URL/api/saved_objects/index-pattern/$INDEX_PATTERN_ID" \
            -d"{\"attributes\":{\"title\":\"$INDEX_PATTERN\",\"timeFieldName\":\"$INDEX_TIME_FIELD\"}}" 2>&1 || true

          echo "Setting default index pattern..."

          # Make it the default index
          curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL -XPOST -H "Content-Type: application/json" -H "$XSRF_HEADER: anything" \
            "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings/defaultIndex" \
            -d"{\"value\":\"$INDEX_PATTERN_ID\"}" || true

          for i in ${OTHER_INDEX_PATTERNS[@]}; do
            IDX_ID="$(echo "$i" | cut -d';' -f1)"
            IDX_NAME="$(echo "$i" | cut -d';' -f2)"
            IDX_TIME_FIELD="$(echo "$i" | cut -d';' -f3)"
            echo "Creating index pattern \"$IDX_NAME\"..."
            curl "${CURL_CONFIG_PARAMS[@]}" -w "\n" -sSL --fail -XPOST -H "Content-Type: application/json" -H "$XSRF_HEADER: anything" \
              "$DASHB_URL/api/saved_objects/index-pattern/$IDX_ID" \
              -d"{\"attributes\":{\"title\":\"$IDX_NAME\",\"timeFieldName\":\"$IDX_TIME_FIELD\"}}" 2>&1 || true
          done

          echo "Importing $DATASTORE_TYPE Dashboards saved objects..."

          # install default dashboards
          DASHBOARDS_IMPORT_DIR="$(mktemp -d -t dashboards-XXXXXX)"
          cp /opt/dashboards/*.json "${DASHBOARDS_IMPORT_DIR}"/
          for i in "${DASHBOARDS_IMPORT_DIR}"/*.json; do
            if [[ "$DATASTORE_TYPE" == "elasticsearch" ]]; then
              # strip out Arkime and NetBox links from dashboards' navigation pane when doing Kibana import (idaholab/Malcolm#286)
              sed -i 's/  \\\\n\[↪ NetBox\](\/netbox\/)  \\\\n\[↪ Arkime\](\/sessions)//' "$i"
              # take care of a few other substitutions
              sed -i 's/opensearchDashboardsAddFilter/kibanaAddFilter/g' "$i"
            fi
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/dashboards/import?force=true" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "@$i"
          done
          rm -rf "${DASHBOARDS_IMPORT_DIR}"

          # beats will no longer import its dashbaords into OpenSearch
          # (see opensearch-project/OpenSearch-Dashboards#656 and
          # opensearch-project/OpenSearch-Dashboards#831). As such, we're going to
          # manually add load our dashboards in /opt/dashboards/beats as well.
          for i in /opt/dashboards/beats/*.json; do
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/dashboards/import?force=true" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "@$i"
          done

          echo "$DATASTORE_TYPE Dashboards saved objects import complete!"

          if [[ "$DATASTORE_TYPE" == "opensearch" ]]; then
            # some features and tweaks like anomaly detection, alerting, etc. only exist in opensearch

            # set dark theme (or not)
            [[ "$DARK_MODE" == "true" ]] && DARK_MODE_ARG='{"value":true}' || DARK_MODE_ARG='{"value":false}'
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings/theme:darkMode" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "$DARK_MODE_ARG"

            # set default dashboard
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings/defaultRoute" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "{\"value\":\"/app/dashboards#/view/${DEFAULT_DASHBOARD}\"}"

            # set default query time range
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d \
              '{"changes":{"timepicker:timeDefaults":"{\n  \"from\": \"now-24h\",\n  \"to\": \"now\",\n  \"mode\": \"quick\"}"}}'

            # turn off telemetry
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/telemetry/v2/optIn" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d '{"enabled":false}'

            # pin filters by default
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings/filters:pinnedByDefault" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d '{"value":true}'

            # enable in-session storage
            curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$DASHB_URL/api/$DASHBOARDS_URI_PATH/settings/state:storeInSessionStorage" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d '{"value":true}'

            # before we go on to create the anomaly detectors, we need to wait for actual arkime_sessions3-* documents
            /data/opensearch_status.sh -w >/dev/null 2>&1
            sleep 60

            echo "Creating $DATASTORE_TYPE anomaly detectors..."

            # Create anomaly detectors here
            for i in /opt/anomaly_detectors/*.json; do
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_anomaly_detection/detectors" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "@$i"
            done

            # trigger a start/stop for the dummy detector to make sure the .opendistro-anomaly-detection-state index gets created
            # see:
            # - https://github.com/opensearch-project/anomaly-detection-dashboards-plugin/issues/109
            # - https://github.com/opensearch-project/anomaly-detection-dashboards-plugin/issues/155
            # - https://github.com/opensearch-project/anomaly-detection-dashboards-plugin/issues/156
            # - https://discuss.opendistrocommunity.dev/t/errors-opening-anomaly-detection-plugin-for-dashboards-after-creation-via-api/7711
            set +e
            DUMMY_DETECTOR_ID=""
            until [[ -n "$DUMMY_DETECTOR_ID" ]]; do
              sleep 5
              DUMMY_DETECTOR_ID="$(curl "${CURL_CONFIG_PARAMS[@]}" -L --fail --silent --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_anomaly_detection/detectors/_search" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "{ \"query\": { \"match\": { \"name\": \"$DUMMY_DETECTOR_NAME\" } } }" | jq '.. | ._id? // empty' 2>/dev/null | head -n 1 | tr -d '"')"
            done
            set -e
            if [[ -n "$DUMMY_DETECTOR_ID" ]]; then
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_anomaly_detection/detectors/$DUMMY_DETECTOR_ID/_start" -H "$XSRF_HEADER:true" -H 'Content-type:application/json'
              sleep 10
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_anomaly_detection/detectors/$DUMMY_DETECTOR_ID/_stop" -H "$XSRF_HEADER:true" -H 'Content-type:application/json'
              sleep 10
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XDELETE "$OPENSEARCH_URL_TO_USE/_plugins/_anomaly_detection/detectors/$DUMMY_DETECTOR_ID" -H "$XSRF_HEADER:true" -H 'Content-type:application/json'
            fi

            echo "$DATASTORE_TYPE anomaly detectors creation complete!"

            echo "Creating $DATASTORE_TYPE alerting objects..."

            # Create notification/alerting objects here

            # notification channels
            for i in /opt/notifications/channels/*.json; do
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_notifications/configs" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "@$i"
            done

            # monitors
            for i in /opt/alerting/monitors/*.json; do
              curl "${CURL_CONFIG_PARAMS[@]}" -L --silent --output /dev/null --show-error -XPOST "$OPENSEARCH_URL_TO_USE/_plugins/_alerting/monitors" -H "$XSRF_HEADER:true" -H 'Content-type:application/json' -d "@$i"
            done

            echo "$DATASTORE_TYPE alerting objects creation complete!"

          fi # DATASTORE_TYPE == opensearch
        fi # stuff to only do for primary
      fi # index pattern not already created check
    fi # dashboards is running
  done # primary vs. secondary
fi # CREATE_OS_ARKIME_SESSION_INDEX is true

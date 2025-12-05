#!/usr/bin/env bash

set +x

# cd to location of this script https://stackoverflow.com/questions/6393551/what-is-the-meaning-of-0-in-a-bash-script
cd "${0%/*}"

npm install
npm run build

mage

zip -vr grafana-clickhouse-datasource.zip dist

aws s3 cp grafana-clickhouse-datasource.zip s3://aven-grafana-apps/grafana-clickhouse-datasource.zip
#!/bin/bash

set -euo pipefail
dir_path=$(dirname $(realpath $0))

AUTHORINO_NAMESPACE=authorino-demo

# create envoy configmap
kubectl -n $AUTHORINO_NAMESPACE apply -f $dir_path/configmap.yaml

# patch news-api deployment adding envoy sidecar
kubectl -n $AUTHORINO_NAMESPACE patch deployment news-api --type=strategic --patch "$(cat $dir_path/envoy-sidecar-patch.yaml)"

# create service for WE-traffic
kubectl -n $AUTHORINO_NAMESPACE apply -f $dir_path/service.yaml

# create route for NS-traffic
kubectl -n $AUTHORINO_NAMESPACE apply -f $dir_path/route.yaml

# delete news-api-internal service - to avoid exposing the service other than through envoy
kubectl -n $AUTHORINO_NAMESPACE delete service/news-api-internal

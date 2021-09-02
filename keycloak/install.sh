#!/bin/bash

set -euo pipefail
dir_path=$(dirname $(realpath $0))

AUTHORINO_NAMESPACE=authorino-demo
KEYCLOAK_NAMESPACE=$AUTHORINO_NAMESPACE

# keycloak-operator
kustomize build $dir_path/install/ | kubectl apply -f -
echo "Waiting until the keycloak operator is ready"
kubectl -n $KEYCLOAK_NAMESPACE wait --timeout=300s --for=condition=Available deployment/keycloak-operator

# keycloak instance
kubectl -n $KEYCLOAK_NAMESPACE apply -f $dir_path/instance.yaml
echo "Waiting until the keycloak instance is ready"
while [ "$(kubectl -n $KEYCLOAK_NAMESPACE get keycloak/keycloak -o jsonpath='{.status.ready}')" != "true" ]; do
  sleep 1
done

# admin console
KEYCLOAK_ADMIN_CONSOLE=$(kubectl -n $KEYCLOAK_NAMESPACE get keycloak/keycloak --output="jsonpath={.status.externalURL}")
KEYCLOAK_CREDENTIAL_SECRET=$(kubectl -n $KEYCLOAK_NAMESPACE get keycloak/keycloak --output="jsonpath={.status.credentialSecret}")
echo "You can then connect to the Keycloak Admin Console at $KEYCLOAK_ADMIN_CONSOLE, with credentials"
echo ""
kubectl -n $KEYCLOAK_NAMESPACE get secret $KEYCLOAK_CREDENTIAL_SECRET -o go-template='{{range $k,$v := .data}}{{printf "%s: " $k}}{{if not $v}}{{$v}}{{else}}{{$v | base64decode}}{{end}}{{"\n"}}{{end}}'

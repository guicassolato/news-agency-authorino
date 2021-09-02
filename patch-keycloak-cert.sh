#!/bin/bash

set -euo pipefail
dir_path=$(dirname $(realpath $0))

AUTHORINO_NAMESPACE=authorino-demo
KEYCLOAK_NAMESPACE=$AUTHORINO_NAMESPACE

# patch keycloak tls cert in authorino
echo quit | openssl s_client -showcerts -servername keycloak-authorino-demo.apps.mycluster.example.local -connect keycloak-authorino-demo.apps.mycluster.example.local:443 | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > dev-eng-ocp4-8.pem
kubectl -n $KEYCLOAK_NAMESPACE create configmap ca-pemstore-dev-eng-ocp4-8 --from-file=dev-eng-ocp4-8.pem
kubectl -n $AUTHORINO_NAMESPACE patch deployment authorino-controller-manager --type=strategic --patch "$(cat $dir_path/keycloak-cert-patch.yaml)"
rm -rf dev-eng-ocp4-8.pem

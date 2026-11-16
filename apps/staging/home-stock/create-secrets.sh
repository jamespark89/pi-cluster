#!/usr/bin/env bash
# Creates Home Stock's secrets in the cluster, once, before the first sync:
# the database password, the app settings, the tunnel credentials, and the
# image pull secret (copied from sunday-fc, same GitHub account).
# Nothing secret is shown on screen or written to disk.
#   bash create-secrets.sh
set -euo pipefail

ns=home-stock
tunnel_id=b4f92423-2c93-4834-b248-2eefd0938b5b # cloudflared tunnel "homestock"

kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"

if kubectl -n "$ns" get secret home-stock-db >/dev/null 2>&1; then
  echo "home-stock-db already exists; leaving it and home-stock-env alone."
else
  pw="$(openssl rand -base64 24 | tr -d '/+=')"
  kubectl -n "$ns" create secret generic home-stock-db --from-literal=POSTGRES_PASSWORD="$pw"
  kubectl -n "$ns" create secret generic home-stock-env \
    --from-literal=DATABASE_URL="postgresql://postgres:$pw@home-stock-db:5432/homestock?schema=public" \
    --from-literal=TIME_ZONE=Australia/Sydney
  unset pw
fi

kubectl -n "$ns" get secret tunnel-credentials >/dev/null 2>&1 ||
  kubectl -n "$ns" create secret generic tunnel-credentials \
    --from-file=credentials.json="$HOME/.cloudflared/$tunnel_id.json"

# Only while the image is private. If the token in sunday-fc's copy is replaced,
# delete this one and run the script again.
kubectl -n "$ns" get secret ghcr-pull >/dev/null 2>&1 ||
  kubectl -n sunday-fc get secret ghcr-pull -o json |
    jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name, namespace: "home-stock"}}' |
    kubectl apply -f - >/dev/null

kubectl -n "$ns" get secrets

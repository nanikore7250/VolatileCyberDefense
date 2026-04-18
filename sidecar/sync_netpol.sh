#!/bin/sh
# VCD Sidecar — NetworkPolicy sync
# Periodically reads blocked IPs from Redis and patches the NetworkPolicy's except[] list.
# Uses the pod's ServiceAccount token to call the Kubernetes API directly.

set -eu

REDIS_URL="${REDIS_URL:-redis://localhost:6379}"
SYNC_INTERVAL="${SYNC_INTERVAL:-30}"
NETPOL_NAME="vcd-block-policy"

K8S_API="https://kubernetes.default.svc"
TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
CA_CERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
NS_FILE="/var/run/secrets/kubernetes.io/serviceaccount/namespace"

log() { echo "[vcd-netpol] $*"; }

build_except_json() {
  ips=$(redis-cli -u "$REDIS_URL" SMEMBERS "vcd:blocked_ips" 2>/dev/null || true)
  if [ -z "$ips" ]; then
    echo "[]"
    return
  fi
  result=$(echo "$ips" | grep -v '^$' | awk '{printf "\"%s/32\",", $0}' | sed 's/,$//')
  echo "[$result]"
}

patch_netpol() {
  token=$(cat "$TOKEN_FILE")
  namespace=$(cat "$NS_FILE")
  except_json=$(build_except_json)

  body=$(printf '{"spec":{"ingress":[{"from":[{"ipBlock":{"cidr":"0.0.0.0/0","except":%s}}],"ports":[{"protocol":"TCP","port":4000}]}]}}' "$except_json")

  result=$(curl -s -o /dev/null -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/merge-patch+json" \
    --cacert "$CA_CERT" \
    "$K8S_API/apis/networking.k8s.io/v1/namespaces/$namespace/networkpolicies/$NETPOL_NAME" \
    -d "$body")

  if [ "$result" = "200" ]; then
    count=$(echo "$except_json" | grep -o '/' | wc -l)
    log "NetworkPolicy updated — ${count} IP(s) blocked at network layer"
  else
    log "NetworkPolicy patch failed (HTTP $result)"
  fi
}

log "Starting NetworkPolicy sync (interval: ${SYNC_INTERVAL}s)"

while true; do
  patch_netpol
  sleep "$SYNC_INTERVAL"
done

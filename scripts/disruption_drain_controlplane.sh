#!/usr/bin/env bash
set -euo pipefail

CONTROL_NODE=${1:-vm1-control}
TARGET_URL=${2:-http://10.0.0.12:30080}

echo "[test] drain control-plane node: ${CONTROL_NODE}"
kubectl drain "${CONTROL_NODE}" --ignore-daemonsets --delete-emptydir-data

echo "[test] probe service during disruption"
for i in $(seq 1 30); do
  if curl -fsS "${TARGET_URL}" > /dev/null; then
    echo "$(date -Iseconds) request ${i}: ok"
  else
    echo "$(date -Iseconds) request ${i}: fail"
  fi
  sleep 1
done

echo "[test] uncordon node"
kubectl uncordon "${CONTROL_NODE}"

echo "[test] post-check"
kubectl get nodes -o wide
kubectl get pods -n demo -o wide

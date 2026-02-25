#!/usr/bin/env bash
set -euo pipefail

TARGET_URL=${1:-http://10.0.0.11:30080}

echo "[test] start background traffic to ${TARGET_URL}"
echo "Run this in parallel while stopping VM2 from your hypervisor/control plane"

for i in $(seq 1 60); do
  if curl -fsS "${TARGET_URL}" > /dev/null; then
    echo "$(date -Iseconds) request ${i}: ok"
  else
    echo "$(date -Iseconds) request ${i}: fail"
  fi
  sleep 1
done

echo "[test] capture cluster status"
kubectl get nodes -o wide
kubectl get pods -n demo -o wide

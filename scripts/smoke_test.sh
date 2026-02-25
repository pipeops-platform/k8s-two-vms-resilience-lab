#!/usr/bin/env bash
set -euo pipefail

TARGET_URL=${1:-http://10.0.0.11:30080}

echo "[smoke] checking cluster resources"
kubectl get nodes -o wide
kubectl get pods -n demo -o wide
kubectl get svc -n demo

echo "[smoke] probing service endpoint: ${TARGET_URL}"
for i in $(seq 1 10); do
  curl -fsS "${TARGET_URL}" > /dev/null
  echo "request ${i}: ok"
  sleep 1
done

echo "[smoke] completed"

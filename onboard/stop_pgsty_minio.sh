#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/minio_common.sh"

if ! [[ -f "$MINIO_PID_FILE" ]]; then
  echo "No MinIO pid file found."
  exit 0
fi

PID="$(cat "$MINIO_PID_FILE")"
if [[ -z "$PID" ]]; then
  rm -f "$MINIO_PID_FILE"
  echo "Removed empty pid file."
  exit 0
fi

if kill -0 "$PID" >/dev/null 2>&1; then
  kill "$PID"
  for _ in $(seq 1 10); do
    if ! kill -0 "$PID" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
fi

rm -f "$MINIO_PID_FILE"
echo "pgsty/minio stopped"

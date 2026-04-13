#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/minio_common.sh"

ensure_minio_dirs

if [[ ! -x "$MINIO_BIN_DIR/minio" || ! -x "$MINIO_BIN_DIR/mcli" ]]; then
  echo "MinIO binaries not found. Run onboard/install_pgsty_minio.sh first." >&2
  exit 1
fi

if is_minio_running; then
  echo "pgsty/minio is already running (pid=$(cat "$MINIO_PID_FILE"))."
else
  rm -f "$MINIO_PID_FILE"

  if is_tcp_port_busy "$MINIO_HOST" "$MINIO_PORT" || \
     is_tcp_port_busy "$MINIO_HOST" "$MINIO_CONSOLE_PORT"; then
    echo "Port ${MINIO_PORT} or ${MINIO_CONSOLE_PORT} is already in use." >&2
    echo "Override MINIO_PORT / MINIO_CONSOLE_PORT in onboard/minio.env and retry." >&2
    exit 1
  fi

  nohup env \
    MINIO_ROOT_USER="$MINIO_ROOT_USER" \
    MINIO_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD" \
    MINIO_SITE_REGION="$MINIO_REGION" \
    "$MINIO_BIN_DIR/minio" server "$MINIO_DATA_DIR" \
      --address "${MINIO_HOST}:${MINIO_PORT}" \
      --console-address "${MINIO_HOST}:${MINIO_CONSOLE_PORT}" \
      >>"$MINIO_LOG_FILE" 2>&1 < /dev/null &
  MINIO_PID="$!"
  echo "$MINIO_PID" > "$MINIO_PID_FILE"

  sleep 1
  if ! kill -0 "$MINIO_PID" >/dev/null 2>&1; then
    echo "pgsty/minio exited early. Check $MINIO_LOG_FILE for details." >&2
    rm -f "$MINIO_PID_FILE"
    exit 1
  fi
fi

wait_for_http "$MINIO_ENDPOINT/minio/health/live" 30

"$MINIO_BIN_DIR/mcli" alias set \
  "$MINIO_ALIAS" \
  "$MINIO_ENDPOINT" \
  "$MINIO_ROOT_USER" \
  "$MINIO_ROOT_PASSWORD" >/dev/null

"$MINIO_BIN_DIR/mcli" mb --ignore-existing "${MINIO_ALIAS}/${MINIO_BUCKET}" >/dev/null

echo "pgsty/minio ready"
echo "endpoint: $MINIO_ENDPOINT"
echo "console:  $MINIO_CONSOLE_URL"
echo "bucket:   $MINIO_BUCKET"

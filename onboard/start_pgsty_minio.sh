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

  if ss -ltn | grep -qE ":(${MINIO_PORT}|${MINIO_CONSOLE_PORT})[[:space:]]"; then
    echo "Port ${MINIO_PORT} or ${MINIO_CONSOLE_PORT} is already in use." >&2
    echo "Override MINIO_PORT / MINIO_CONSOLE_PORT in onboard/minio.env and retry." >&2
    exit 1
  fi

  setsid bash -c '
    echo $$ > "$1"
    exec env \
      MINIO_ROOT_USER="$2" \
      MINIO_ROOT_PASSWORD="$3" \
      MINIO_SITE_REGION="$4" \
      "$5" server "$6" \
        --address "$7" \
        --console-address "$8"
  ' bash \
    "$MINIO_PID_FILE" \
    "$MINIO_ROOT_USER" \
    "$MINIO_ROOT_PASSWORD" \
    "$MINIO_REGION" \
    "$MINIO_BIN_DIR/minio" \
    "$MINIO_DATA_DIR" \
    "${MINIO_HOST}:${MINIO_PORT}" \
    "${MINIO_HOST}:${MINIO_CONSOLE_PORT}" \
    >>"$MINIO_LOG_FILE" 2>&1 < /dev/null &

  sleep 1
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

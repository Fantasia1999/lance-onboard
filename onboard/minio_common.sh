#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/env.sh"

MINIO_ENV_FILE="${MINIO_ENV_FILE:-$SCRIPT_DIR/minio.env}"
if [[ -f "$MINIO_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$MINIO_ENV_FILE"
fi

LOCAL_ROOT="${LOCAL_ROOT:-$PROJECT_ROOT/local}"
MINIO_BIN_DIR="${MINIO_BIN_DIR:-$LOCAL_ROOT/bin}"
MINIO_DOWNLOAD_DIR="${MINIO_DOWNLOAD_DIR:-$LOCAL_ROOT/downloads}"
MINIO_HOME="${MINIO_HOME:-$LOCAL_ROOT/minio}"
MINIO_DATA_DIR="${MINIO_DATA_DIR:-$MINIO_HOME/data}"
MINIO_LOG_DIR="${MINIO_LOG_DIR:-$MINIO_HOME/logs}"
MINIO_RUN_DIR="${MINIO_RUN_DIR:-$MINIO_HOME/run}"
MINIO_PID_FILE="${MINIO_PID_FILE:-$MINIO_RUN_DIR/minio.pid}"
MINIO_LOG_FILE="${MINIO_LOG_FILE:-$MINIO_LOG_DIR/minio.log}"
MC_CONFIG_DIR="${MC_CONFIG_DIR:-$LOCAL_ROOT/mc}"

MINIO_ROOT_USER="${MINIO_ROOT_USER:-ACCESSKEY}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-SECRETKEY}"
MINIO_HOST="${MINIO_HOST:-127.0.0.1}"
MINIO_PORT="${MINIO_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
MINIO_REGION="${MINIO_REGION:-us-east-1}"
MINIO_BUCKET="${MINIO_BUCKET:-lancedb-dev}"
MINIO_ALIAS="${MINIO_ALIAS:-pgsty}"

MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://${MINIO_HOST}:${MINIO_PORT}}"
MINIO_CONSOLE_URL="${MINIO_CONSOLE_URL:-http://${MINIO_HOST}:${MINIO_CONSOLE_PORT}}"

PGSTY_MINIO_REPO="${PGSTY_MINIO_REPO:-pgsty/minio}"
PGSTY_MC_REPO="${PGSTY_MC_REPO:-pgsty/mc}"
PGSTY_MINIO_RELEASE="${PGSTY_MINIO_RELEASE:-latest}"
PGSTY_MC_RELEASE="${PGSTY_MC_RELEASE:-latest}"

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$MINIO_ROOT_USER}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$MINIO_ROOT_PASSWORD}"
export AWS_REGION="${AWS_REGION:-$MINIO_REGION}"
export AWS_ALLOW_HTTP="${AWS_ALLOW_HTTP:-true}"
export AWS_ENDPOINT="${AWS_ENDPOINT:-$MINIO_ENDPOINT}"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-$MINIO_ENDPOINT}"
export MC_CONFIG_DIR

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

ensure_minio_dirs() {
  mkdir -p \
    "$MINIO_BIN_DIR" \
    "$MINIO_DOWNLOAD_DIR" \
    "$MINIO_DATA_DIR" \
    "$MINIO_LOG_DIR" \
    "$MINIO_RUN_DIR" \
    "$MC_CONFIG_DIR"
}

release_api_url() {
  local repo="$1"
  local release_ref="$2"

  if [[ "$release_ref" == "latest" ]]; then
    printf "https://api.github.com/repos/%s/releases/latest" "$repo"
  else
    printf "https://api.github.com/repos/%s/releases/tags/%s" "$repo" "$release_ref"
  fi
}

resolve_release_asset() {
  local repo="$1"
  local release_ref="$2"
  local suffix="$3"

  curl -fsSL "$(release_api_url "$repo" "$release_ref")" | \
    "$PYTHON_BIN" -c '
import json
import sys

suffix = sys.argv[1]
data = json.load(sys.stdin)
for asset in data.get("assets", []):
    url = asset.get("browser_download_url", "")
    if url.endswith(suffix):
        print(url)
        raise SystemExit(0)
raise SystemExit(f"no asset ending with {suffix!r} found")
' "$suffix"
}

download_with_retries() {
  local url="$1"
  local output="$2"

  curl --retry "${CURL_RETRY_COUNT:-5}" --retry-all-errors --retry-delay 2 \
    -fL "$url" -o "$output"
}

verify_checksum_from_file() {
  local checksum_file="$1"
  local artifact="$2"
  local artifact_name

  artifact_name="$(basename "$artifact")"
  local expected
  expected="$(grep "  ${artifact_name}\$" "$checksum_file" | awk '{print $1}' | head -n 1)"

  if [[ -z "$expected" ]]; then
    echo "Failed to find checksum for $artifact_name in $checksum_file" >&2
    exit 1
  fi

  local actual
  actual="$(sha256sum "$artifact" | awk '{print $1}')"
  if [[ "$expected" != "$actual" ]]; then
    echo "Checksum mismatch for $artifact_name" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
}

extract_binary_from_archive() {
  local archive="$1"
  local binary_name="$2"
  local dest="$3"
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/minio-extract.XXXXXX)"

  tar -xzf "$archive" -C "$tmp_dir"
  local candidate
  candidate="$(find "$tmp_dir" -type f -name "$binary_name" | head -n 1)"

  if [[ -z "$candidate" ]]; then
    echo "Failed to find binary '$binary_name' in $archive" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  install -m 0755 "$candidate" "$dest"
  rm -rf "$tmp_dir"
}

wait_for_http() {
  local url="$1"
  local timeout_seconds="${2:-30}"
  local start_ts
  start_ts="$(date +%s)"

  while true; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi

    if (( $(date +%s) - start_ts >= timeout_seconds )); then
      echo "Timed out waiting for $url" >&2
      return 1
    fi
    sleep 1
  done
}

is_minio_running() {
  if [[ -f "$MINIO_PID_FILE" ]]; then
    local pid
    pid="$(cat "$MINIO_PID_FILE")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
  fi
  return 1
}

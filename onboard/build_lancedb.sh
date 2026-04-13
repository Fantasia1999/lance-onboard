#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/env.sh"

REPO_ROOT="${LANCEDB_REPO:-$PROJECT_ROOT/lancedb}"

if [[ ! -d "$REPO_ROOT/python" ]]; then
  echo "Could not find lancedb repo at: $REPO_ROOT" >&2
  echo "Set LANCEDB_REPO to the local lancedb checkout and re-run." >&2
  exit 1
fi

if [[ -z "${PYTHON_BIN:-}" || ! -x "${PYTHON_BIN:-}" ]]; then
  echo "Missing required Python interpreter. Set PYTHON_BIN or install python3.12." >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "Missing cargo in PATH. Install Rust and re-run." >&2
  exit 1
fi

if ! command -v protoc >/dev/null 2>&1; then
  echo "Missing protoc in PATH. Install protoc and re-run." >&2
  exit 1
fi

VENV_PYTHON="$REPO_ROOT/python/.venv/bin/python"

if [[ ! -x "$VENV_PYTHON" ]]; then
  "$PYTHON_BIN" -m venv "$REPO_ROOT/python/.venv"
fi

append_index_url() {
  local current="${1:-}"
  local url="$2"

  case " $current " in
    *" $url "*) printf "%s" "$current" ;;
    *) printf "%s" "${current:+$current }$url" ;;
  esac
}

MANDATORY_EXTRA_INDEXES=(
  "https://pypi.fury.io/lance-format/"
  "https://pypi.fury.io/lancedb/"
)

for url in "${MANDATORY_EXTRA_INDEXES[@]}"; do
  PIP_EXTRA_INDEX_URL="$(append_index_url "${PIP_EXTRA_INDEX_URL:-}" "$url")"
  UV_INDEX="$(append_index_url "${UV_INDEX:-${PIP_EXTRA_INDEX_URL:-}}" "$url")"
done

export PIP_EXTRA_INDEX_URL
export UV_INDEX

"$VENV_PYTHON" -m pip install \
  --retries "${PIP_INSTALL_RETRIES:-10}" \
  --timeout "${PIP_INSTALL_TIMEOUT:-120}" \
  -U pip maturin

cd "$REPO_ROOT/python"
exec "$REPO_ROOT/python/.venv/bin/maturin" develop -j "$CARGO_BUILD_JOBS"

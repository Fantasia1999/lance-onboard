#!/usr/bin/env bash

# Source this file before running local onboard checks or builds.
# It wires user-local Python, Rust, and protoc installations into PATH.
# It also points helper scripts at the sibling lancedb repo by default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIRROR_ENV_FILE="$SCRIPT_DIR/mirror.env"

if [[ -f "$MIRROR_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$MIRROR_ENV_FILE"
fi

if [[ -z "${LANCEDB_REPO:-}" && -d "$PROJECT_ROOT/lancedb" ]]; then
  export LANCEDB_REPO="$PROJECT_ROOT/lancedb"
fi

if [[ -d "$HOME/.local/bin" ]]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi

if [[ -d "$HOME/.cargo/bin" ]]; then
  case ":$PATH:" in
    *":$HOME/.cargo/bin:"*) ;;
    *) export PATH="$HOME/.cargo/bin:$PATH" ;;
  esac
fi

if [[ -z "${PYTHON_BIN:-}" ]]; then
  if command -v uv >/dev/null 2>&1; then
    UV_PYTHON_BIN="$(uv python find 3.12 2>/dev/null || true)"
    if [[ -n "${UV_PYTHON_BIN:-}" && -x "${UV_PYTHON_BIN:-}" ]]; then
      export PYTHON_BIN="$UV_PYTHON_BIN"
    fi
  fi

  if [[ -z "${PYTHON_BIN:-}" ]] && command -v python3.12 >/dev/null 2>&1; then
    export PYTHON_BIN="$(command -v python3.12)"
  elif [[ -z "${PYTHON_BIN:-}" ]] && command -v python3 >/dev/null 2>&1; then
    export PYTHON_BIN="$(command -v python3)"
  fi
fi

if [[ -n "${PYTHON_BIN:-}" ]]; then
  PYTHON_DIR="$(dirname "$PYTHON_BIN")"
  case ":$PATH:" in
    *":$PYTHON_DIR:"*) ;;
    *) export PATH="$PYTHON_DIR:$PATH" ;;
  esac
  export PYO3_PYTHON="${PYO3_PYTHON:-$PYTHON_BIN}"
fi

if command -v protoc >/dev/null 2>&1; then
  export PROTOC="${PROTOC:-$(command -v protoc)}"
fi

if [[ -n "${PIP_INDEX_URL:-}" && -z "${UV_DEFAULT_INDEX:-}" ]]; then
  export UV_DEFAULT_INDEX="$PIP_INDEX_URL"
fi

if [[ -n "${PIP_EXTRA_INDEX_URL:-}" && -z "${UV_INDEX:-}" ]]; then
  export UV_INDEX="$PIP_EXTRA_INDEX_URL"
fi

export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-120}"
export UV_HTTP_RETRIES="${UV_HTTP_RETRIES:-5}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$(nproc)}"

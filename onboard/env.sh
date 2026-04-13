#!/usr/bin/env bash

# Source this file before running local onboard checks or builds.
# It wires user-local Python, Rust, and protoc installations into PATH.
# It also points helper scripts at the sibling lancedb repo by default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIRROR_ENV_FILE="$SCRIPT_DIR/mirror.env"

prepend_path_once() {
  local path_entry="$1"
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

python_version_ge() {
  local python_bin="$1"
  local min_version="$2"
  local current_version
  local IFS=.
  local -a current_parts min_parts
  local i

  [[ -n "$python_bin" && -x "$python_bin" ]] || return 1

  current_version="$("$python_bin" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")' 2>/dev/null || true)"
  [[ -n "$current_version" ]] || return 1

  current_parts=($current_version)
  min_parts=($min_version)

  for (( i = 0; i < ${#min_parts[@]}; i++ )); do
    local current_part="${current_parts[i]:-0}"
    local min_part="${min_parts[i]:-0}"
    if (( current_part > min_part )); then
      return 0
    fi
    if (( current_part < min_part )); then
      return 1
    fi
  done

  return 0
}

detect_build_jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  elif command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
  elif command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
  else
    echo 1
  fi
}

if [[ -f "$MIRROR_ENV_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$MIRROR_ENV_FILE"
fi

if [[ -z "${LANCEDB_REPO:-}" && -d "$PROJECT_ROOT/lancedb" ]]; then
  export LANCEDB_REPO="$PROJECT_ROOT/lancedb"
fi

prepend_path_once "$HOME/.local/bin"
prepend_path_once "$HOME/.cargo/bin"

PYTHON_MIN_VERSION="${PYTHON_MIN_VERSION:-3.10}"

if [[ -n "${PYTHON_BIN:-}" ]] && ! python_version_ge "${PYTHON_BIN:-}" "$PYTHON_MIN_VERSION"; then
  unset PYTHON_BIN
fi

if [[ -z "${PYTHON_BIN:-}" ]]; then
  if command -v uv >/dev/null 2>&1; then
    UV_PYTHON_BIN="$(uv python find "${PYTHON_VERSION:-3.12}" 2>/dev/null || true)"
    if python_version_ge "${UV_PYTHON_BIN:-}" "$PYTHON_MIN_VERSION"; then
      export PYTHON_BIN="$UV_PYTHON_BIN"
    fi
  fi

  if [[ -z "${PYTHON_BIN:-}" ]] && command -v python3.12 >/dev/null 2>&1; then
    PYTHON_CANDIDATE="$(command -v python3.12)"
    if python_version_ge "$PYTHON_CANDIDATE" "$PYTHON_MIN_VERSION"; then
      export PYTHON_BIN="$PYTHON_CANDIDATE"
    fi
  fi

  if [[ -z "${PYTHON_BIN:-}" ]] && command -v python3 >/dev/null 2>&1; then
    PYTHON_CANDIDATE="$(command -v python3)"
    if python_version_ge "$PYTHON_CANDIDATE" "$PYTHON_MIN_VERSION"; then
      export PYTHON_BIN="$PYTHON_CANDIDATE"
    fi
  fi

  if [[ -z "${PYTHON_BIN:-}" ]] && command -v python >/dev/null 2>&1; then
    PYTHON_CANDIDATE="$(command -v python)"
    if python_version_ge "$PYTHON_CANDIDATE" "$PYTHON_MIN_VERSION"; then
      export PYTHON_BIN="$PYTHON_CANDIDATE"
    fi
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
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$(detect_build_jobs)}"

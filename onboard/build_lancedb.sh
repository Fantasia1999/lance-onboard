#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/env.sh"

REPO_ROOT="${LANCEDB_REPO:-$PROJECT_ROOT/lancedb}"
REPO_CARGO_TOML="$REPO_ROOT/Cargo.toml"

if [[ ! -d "$REPO_ROOT/python" ]]; then
  echo "Could not find lancedb repo at: $REPO_ROOT" >&2
  echo "Set LANCEDB_REPO to the local lancedb checkout and re-run." >&2
  exit 1
fi

if [[ -z "${PYTHON_BIN:-}" || ! -x "${PYTHON_BIN:-}" ]]; then
  echo "Missing required Python interpreter. Run onboard/install_prereqs.sh first." >&2
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

version_ge() {
  local IFS=.
  local -a v1=($1) v2=($2)
  local i
  for (( i = 0; i < ${#v2[@]}; i++ )); do
    local a="${v1[i]:-0}" b="${v2[i]:-0}"
    if (( a > b )); then return 0; fi
    if (( a < b )); then return 1; fi
  done
  return 0
}

detect_repo_rust_min_version() {
  [[ -f "$REPO_CARGO_TOML" ]] || return 1
  sed -n 's/^[[:space:]]*rust-version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_CARGO_TOML" | head -n 1
}

detect_rustup_toolchain_for_build() {
  if [[ -n "${RUSTUP_TOOLCHAIN:-}" ]]; then
    printf "%s" "$RUSTUP_TOOLCHAIN"
    return 0
  fi

  command -v rustup >/dev/null 2>&1 || return 1

  (
    cd "$PROJECT_ROOT"
    rustup show active-toolchain 2>/dev/null | sed 's/ .*//' | head -n 1
  )
}

detect_rust_version_for_build() {
  local toolchain="${1:-}"

  if [[ -n "$toolchain" ]]; then
    env RUSTUP_TOOLCHAIN="$toolchain" rustc --version 2>/dev/null | sed 's/rustc \([^ ]*\).*/\1/'
  else
    rustc --version 2>/dev/null | sed 's/rustc \([^ ]*\).*/\1/'
  fi
}

RUST_BUILD_MIN_VERSION="${RUST_BUILD_MIN_VERSION:-$(detect_repo_rust_min_version || true)}"
RUST_BUILD_MIN_VERSION="${RUST_BUILD_MIN_VERSION:-${RUST_MIN_VERSION:-1.85.0}}"
BUILD_RUSTUP_TOOLCHAIN="$(detect_rustup_toolchain_for_build || true)"
CURRENT_RUST_VERSION="$(detect_rust_version_for_build "$BUILD_RUSTUP_TOOLCHAIN")"

if [[ -z "$CURRENT_RUST_VERSION" ]]; then
  echo "Failed to determine the Rust version that build_lancedb.sh will use." >&2
  exit 1
fi

if ! version_ge "$CURRENT_RUST_VERSION" "$RUST_BUILD_MIN_VERSION"; then
  echo "Rust $CURRENT_RUST_VERSION is below the minimum required to build lancedb ($RUST_BUILD_MIN_VERSION)." >&2
  echo "Run onboard/install_prereqs.sh to install a compatible Rust toolchain and re-run." >&2
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
if [[ -n "$BUILD_RUSTUP_TOOLCHAIN" ]]; then
  echo "build-lancedb: using Rust toolchain $BUILD_RUSTUP_TOOLCHAIN (rustc $CURRENT_RUST_VERSION)"
  exec env RUSTUP_TOOLCHAIN="$BUILD_RUSTUP_TOOLCHAIN" \
    "$REPO_ROOT/python/.venv/bin/maturin" develop -j "$CARGO_BUILD_JOBS"
fi

echo "build-lancedb: using Rust $CURRENT_RUST_VERSION"
exec "$REPO_ROOT/python/.venv/bin/maturin" develop -j "$CARGO_BUILD_JOBS"

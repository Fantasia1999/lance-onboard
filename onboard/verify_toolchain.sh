#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

require_command cargo
require_command rustc
require_command protoc

if [[ -z "${PYTHON_BIN:-}" || ! -x "${PYTHON_BIN:-}" ]]; then
  echo "Missing required Python interpreter. Run onboard/install_prereqs.sh first." >&2
  exit 1
fi

echo "verify-toolchain: python=$PYTHON_BIN ($("$PYTHON_BIN" --version 2>&1))"
echo "verify-toolchain: cargo=$(command -v cargo) ($(cargo --version 2>&1))"
echo "verify-toolchain: rustc=$(command -v rustc) ($(rustc --version 2>&1))"
echo "verify-toolchain: protoc=$(command -v protoc) ($(protoc --version 2>&1))"
echo "verify-toolchain: CARGO_BUILD_JOBS=$CARGO_BUILD_JOBS"

"$PYTHON_BIN" "$SCRIPT_DIR/python_env_check.py"

cargo run --manifest-path "$SCRIPT_DIR/rust_native_check/Cargo.toml" --quiet
cargo run --manifest-path "$SCRIPT_DIR/rust_protoc_check/Cargo.toml" --quiet

echo "verify-toolchain: all checks passed"

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

linux_c_toolchain_hint() {
  local os_id=""
  local os_like=""

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    os_id="${ID:-}"
    os_like="${ID_LIKE:-}"
  fi

  case " ${os_like} ${os_id} " in
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*)
      echo "Install GCC/Make first. On Fedora/RHEL/CentOS/Rocky/AlmaLinux, run: sudo dnf install -y gcc gcc-c++ make" >&2
      echo "If you are on an older RHEL/CentOS release without dnf, use: sudo yum install -y gcc gcc-c++ make" >&2
      ;;
    *)
      echo "Install GCC/Make first. On Debian/Ubuntu/WSL, run: sudo apt update && sudo apt install -y build-essential" >&2
      echo "On Fedora/RHEL/CentOS/Rocky/AlmaLinux, run: sudo dnf install -y gcc gcc-c++ make" >&2
      ;;
  esac
}

require_system_c_toolchain() {
  if command -v cc >/dev/null 2>&1; then
    return 0
  fi

  echo "Missing required system C toolchain: 'cc' was not found on PATH." >&2
  case "$(uname -s)" in
    Linux)
      linux_c_toolchain_hint
      ;;
    Darwin)
      echo "Install Xcode Command Line Tools first: xcode-select --install" >&2
      ;;
  esac
  exit 1
}

require_command cargo
require_command rustc
require_command protoc
require_system_c_toolchain

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

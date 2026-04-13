#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/env.sh"

# ── Colour helpers (disabled when stdout is not a terminal) ──────────────
if [[ -t 1 ]]; then
  _C_GREEN='\033[0;32m'; _C_YELLOW='\033[0;33m'
  _C_BLUE='\033[0;34m';  _C_RED='\033[0;31m'; _C_RESET='\033[0m'
else
  _C_GREEN=''; _C_YELLOW=''; _C_BLUE=''; _C_RED=''; _C_RESET=''
fi

info()    { printf "${_C_BLUE}[INFO]${_C_RESET}  %s\n" "$*"; }
ok()      { printf "${_C_GREEN}[ OK ]${_C_RESET}  %s\n" "$*"; }
skip_msg(){ printf "${_C_YELLOW}[SKIP]${_C_RESET}  %s\n" "$*"; }
warn()    { printf "${_C_YELLOW}[WARN]${_C_RESET}  %s\n" "$*" >&2; }
fail()    { printf "${_C_RED}[FAIL]${_C_RESET}  %s\n" "$*" >&2; exit 1; }

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "Missing required command: $name"
  fi
}

prepend_path_once() {
  local path_entry="$1"
  case ":$PATH:" in
    *":$path_entry:"*) ;;
    *) export PATH="$path_entry:$PATH" ;;
  esac
}

# ── Version comparison: returns 0 when $1 >= $2 (dot-separated) ─────────
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

# ── OS / architecture detection for protoc archive naming ────────────────
detect_protoc_os() {
  case "$(uname -s)" in
    Linux)  echo "linux" ;;
    Darwin) echo "osx" ;;
    *)      fail "Unsupported OS: $(uname -s)" ;;
  esac
}

detect_protoc_arch() {
  case "$(uname -m)" in
    x86_64|amd64)   echo "x86_64" ;;
    aarch64|arm64)   echo "aarch_64" ;;
    *)               fail "Unsupported architecture: $(uname -m)" ;;
  esac
}

# ── Tuneable defaults ────────────────────────────────────────────────────
require_command curl

UV_INSTALLER_URL="${UV_INSTALLER_URL:-https://astral.sh/uv/install.sh}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
PYTHON_MIN_VERSION="${PYTHON_MIN_VERSION:-3.10}"
# Rust edition 2024 (used by helper crates) requires >= 1.85
RUST_MIN_VERSION="${RUST_MIN_VERSION:-1.85.0}"
PROTOC_VERSION="${PROTOC_VERSION:-34.1}"

_PROTOC_OS="$(detect_protoc_os)"
_PROTOC_ARCH="$(detect_protoc_arch)"
PROTOC_ARCHIVE_NAME="${PROTOC_ARCHIVE_NAME:-protoc-${PROTOC_VERSION}-${_PROTOC_OS}-${_PROTOC_ARCH}.zip}"
RUSTUP_INIT_URL="${RUSTUP_INIT_URL:-https://sh.rustup.rs}"
PROTOC_DOWNLOAD_URL="${PROTOC_DOWNLOAD_URL:-https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ARCHIVE_NAME}}"
CURL_RETRY_COUNT="${CURL_RETRY_COUNT:-5}"

SUMMARY=()   # collects one-line descriptions of what happened

ensure_uv() {
  if command -v uv >/dev/null 2>&1; then
    return 0
  fi

  info "Installing uv via the official installer …"
  prepend_path_once "$HOME/.local/bin"
  curl --retry "$CURL_RETRY_COUNT" --retry-all-errors --retry-delay 2 -LsSf \
    "$UV_INSTALLER_URL" | env UV_NO_MODIFY_PATH=1 sh

  if command -v uv >/dev/null 2>&1; then
    ok "uv installed at $(command -v uv)"
    SUMMARY+=("uv      : installed via official installer")
    return 0
  fi

  fail "uv installation completed but 'uv' is still not on PATH."
}

refresh_python_bin() {
  local candidate=""

  if command -v uv >/dev/null 2>&1; then
    candidate="$(uv python find "$PYTHON_VERSION" 2>/dev/null || true)"
  fi

  if [[ -z "$candidate" ]] && command -v python3 >/dev/null 2>&1; then
    candidate="$(command -v python3)"
  fi

  if [[ -z "$candidate" ]] && command -v python >/dev/null 2>&1; then
    candidate="$(command -v python)"
  fi

  if [[ -n "$candidate" && -x "$candidate" ]]; then
    export PYTHON_BIN="$candidate"
    export PYO3_PYTHON="${PYO3_PYTHON:-$candidate}"
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  1. Python
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Python …"

_python_satisfied=false

# Check PYTHON_BIN (may already be set by env.sh) or common interpreters.
for _candidate in "${PYTHON_BIN:-}" python3 python; do
  [[ -z "$_candidate" ]] && continue
  if command -v "$_candidate" >/dev/null 2>&1; then
    _py_ver="$("$_candidate" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")'  2>/dev/null || true)"
    if [[ -n "$_py_ver" ]] && version_ge "$_py_ver" "$PYTHON_MIN_VERSION"; then
      skip_msg "Python $_py_ver already installed (>= $PYTHON_MIN_VERSION)"
      _python_satisfied=true
      SUMMARY+=("Python  : skipped — $_py_ver already present")
      break
    fi
  fi
done

if ! $_python_satisfied; then
  ensure_uv

  info "Installing Python $PYTHON_VERSION via uv …"
  uv python install "$PYTHON_VERSION"
  refresh_python_bin
  ok "Python $PYTHON_VERSION installed via uv"
  SUMMARY+=("Python  : installed $PYTHON_VERSION via uv")
fi

# ═══════════════════════════════════════════════════════════════════════════
#  2. Rust
# ═══════════════════════════════════════════════════════════════════════════
info "Checking Rust …"

# Source cargo env so rustc / rustup are visible.
if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

_rust_satisfied=false

if command -v rustc >/dev/null 2>&1; then
  _rust_ver="$(rustc --version | sed 's/rustc \([^ ]*\).*/\1/')"
  if version_ge "$_rust_ver" "$RUST_MIN_VERSION"; then
    skip_msg "Rust $_rust_ver already installed (>= $RUST_MIN_VERSION)"
    _rust_satisfied=true
    SUMMARY+=("Rust    : skipped — $_rust_ver already present")
  else
    warn "Rust $_rust_ver is below minimum $RUST_MIN_VERSION — will update"
  fi
fi

if ! $_rust_satisfied; then
  if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    info "Installing Rust (stable) via rustup …"
    curl --retry "$CURL_RETRY_COUNT" --retry-all-errors --retry-delay 2 \
      --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INIT_URL" | \
      sh -s -- -y --default-toolchain stable --profile minimal
    # Reload so rustc is visible.
    if [[ -f "$HOME/.cargo/env" ]]; then
      # shellcheck source=/dev/null
      source "$HOME/.cargo/env"
    fi
    SUMMARY+=("Rust    : installed stable via rustup")
  else
    info "Updating Rust to stable via rustup …"
    rustup toolchain install stable --profile minimal
    rustup default stable
    SUMMARY+=("Rust    : updated to stable via rustup")
  fi
  ok "Rust $(rustc --version | sed 's/rustc \([^ ]*\).*/\1/') ready"
fi

require_command rustup
require_command rustc

# ═══════════════════════════════════════════════════════════════════════════
#  3. protoc
# ═══════════════════════════════════════════════════════════════════════════
info "Checking protoc …"

_protoc_satisfied=false

if command -v protoc >/dev/null 2>&1; then
  _protoc_ver="$(protoc --version | sed 's/libprotoc //')"
  if version_ge "$_protoc_ver" "$PROTOC_VERSION"; then
    skip_msg "protoc $_protoc_ver already installed (>= $PROTOC_VERSION)"
    _protoc_satisfied=true
    SUMMARY+=("protoc  : skipped — $_protoc_ver already present")
  else
    info "protoc $_protoc_ver is below $PROTOC_VERSION — will update"
  fi
fi

if ! $_protoc_satisfied; then
  # Find a Python interpreter for zip extraction.
  _py_bin="${PYTHON_BIN:-}"
  if [[ -z "$_py_bin" ]]; then
    _py_bin="$(uv python find "$PYTHON_VERSION" 2>/dev/null || command -v python3 || true)"
  fi
  if [[ -z "$_py_bin" || ! -x "$_py_bin" ]]; then
    fail "Cannot find a Python interpreter for protoc zip extraction."
  fi

  INSTALL_DIR="$HOME/.local/opt/protoc-$PROTOC_VERSION"
  BIN_DIR="$HOME/.local/bin"
  TMP_ZIP="$(mktemp /tmp/protoc.XXXXXX.zip)"

  mkdir -p "$INSTALL_DIR" "$BIN_DIR"
  rm -rf "$INSTALL_DIR"/*

  info "Downloading protoc $PROTOC_VERSION for ${_PROTOC_OS}/${_PROTOC_ARCH} …"
  curl --retry "$CURL_RETRY_COUNT" --retry-all-errors --retry-delay 2 -L \
    "$PROTOC_DOWNLOAD_URL" -o "$TMP_ZIP"
  "$_py_bin" -m zipfile -e "$TMP_ZIP" "$INSTALL_DIR"
  chmod +x "$INSTALL_DIR/bin/protoc"
  ln -sf "$INSTALL_DIR/bin/protoc" "$BIN_DIR/protoc"
  rm -f "$TMP_ZIP"

  _installed_ver="$("$BIN_DIR/protoc" --version | sed 's/libprotoc //')"
  ok "protoc $_installed_ver installed"
  SUMMARY+=("protoc  : installed $_installed_ver")
fi

# ═══════════════════════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════════════════════
echo ""
info "══════ Prerequisites Summary ══════"
for _line in "${SUMMARY[@]}"; do
  echo "  • $_line"
done
echo ""
ok "All prerequisites ready!"

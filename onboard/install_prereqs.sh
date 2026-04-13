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

require_command curl
require_command uv

PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-1.94.0}"
PROTOC_VERSION="${PROTOC_VERSION:-34.1}"
PROTOC_ARCHIVE_NAME="${PROTOC_ARCHIVE_NAME:-protoc-${PROTOC_VERSION}-linux-x86_64.zip}"
RUSTUP_INIT_URL="${RUSTUP_INIT_URL:-https://sh.rustup.rs}"
PROTOC_DOWNLOAD_URL="${PROTOC_DOWNLOAD_URL:-https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/${PROTOC_ARCHIVE_NAME}}"
CURL_RETRY_COUNT="${CURL_RETRY_COUNT:-5}"

uv python install "$PYTHON_VERSION"

if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl --retry "$CURL_RETRY_COUNT" --retry-all-errors --retry-delay 2 \
    --proto '=https' --tlsv1.2 -sSf "$RUSTUP_INIT_URL" | \
    sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN" --profile minimal
fi

if [[ -f "$HOME/.cargo/env" ]]; then
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
fi

require_command rustup
rustup toolchain install "$RUST_TOOLCHAIN"
rustup default "$RUST_TOOLCHAIN"

PY_BIN="${PYTHON_BIN:-$(uv python find "$PYTHON_VERSION")}"
INSTALL_DIR="$HOME/.local/opt/protoc-$PROTOC_VERSION"
BIN_DIR="$HOME/.local/bin"
TMP_ZIP="$(mktemp /tmp/protoc.XXXXXX.zip)"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
rm -rf "$INSTALL_DIR"/*

curl --retry "$CURL_RETRY_COUNT" --retry-all-errors --retry-delay 2 -L \
  "$PROTOC_DOWNLOAD_URL" -o "$TMP_ZIP"
"$PY_BIN" -m zipfile -e "$TMP_ZIP" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/bin/protoc"
ln -sf "$INSTALL_DIR/bin/protoc" "$BIN_DIR/protoc"
rm -f "$TMP_ZIP"

"$BIN_DIR/protoc" --version

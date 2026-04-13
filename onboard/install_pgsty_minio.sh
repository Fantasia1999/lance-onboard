#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/minio_common.sh"

require_command curl
require_command tar

if [[ -z "${PYTHON_BIN:-}" || ! -x "${PYTHON_BIN:-}" ]]; then
  echo "Missing required Python interpreter. Run onboard/install_prereqs.sh first." >&2
  exit 1
fi

ensure_minio_dirs

if [[ -x "$MINIO_BIN_DIR/minio" && -x "$MINIO_BIN_DIR/mcli" ]]; then
  echo "MinIO binaries already installed:"
  echo "  minio: $("$MINIO_BIN_DIR/minio" --version 2>&1 | head -n1)"
  echo "  mcli:  $("$MINIO_BIN_DIR/mcli" --version 2>&1 | head -n1)"
  echo "To reinstall, remove $MINIO_BIN_DIR/{minio,mcli} and re-run."
  exit 0
fi

ARCHIVE_SUFFIX="${MINIO_ARCHIVE_OS}_${MINIO_ARCHIVE_ARCH}.tar.gz"

MINIO_ARCHIVE_URL="$(resolve_release_asset "$PGSTY_MINIO_REPO" "$PGSTY_MINIO_RELEASE" "$ARCHIVE_SUFFIX")"
MINIO_CHECKSUMS_URL="$(resolve_release_asset "$PGSTY_MINIO_REPO" "$PGSTY_MINIO_RELEASE" "checksums.txt")"
MC_ARCHIVE_URL="$(resolve_release_asset "$PGSTY_MC_REPO" "$PGSTY_MC_RELEASE" "$ARCHIVE_SUFFIX")"
MC_CHECKSUMS_URL="$(resolve_release_asset "$PGSTY_MC_REPO" "$PGSTY_MC_RELEASE" "checksums.txt")"

MINIO_ARCHIVE="$MINIO_DOWNLOAD_DIR/$(basename "$MINIO_ARCHIVE_URL")"
MINIO_CHECKSUMS="$MINIO_DOWNLOAD_DIR/$(basename "$MINIO_CHECKSUMS_URL")"
MC_ARCHIVE="$MINIO_DOWNLOAD_DIR/$(basename "$MC_ARCHIVE_URL")"
MC_CHECKSUMS="$MINIO_DOWNLOAD_DIR/$(basename "$MC_CHECKSUMS_URL")"

download_with_retries "$MINIO_ARCHIVE_URL" "$MINIO_ARCHIVE"
download_with_retries "$MINIO_CHECKSUMS_URL" "$MINIO_CHECKSUMS"
download_with_retries "$MC_ARCHIVE_URL" "$MC_ARCHIVE"
download_with_retries "$MC_CHECKSUMS_URL" "$MC_CHECKSUMS"

verify_checksum_from_file "$MINIO_CHECKSUMS" "$MINIO_ARCHIVE"
verify_checksum_from_file "$MC_CHECKSUMS" "$MC_ARCHIVE"

extract_binary_from_archive "$MINIO_ARCHIVE" "minio" "$MINIO_BIN_DIR/minio"
extract_binary_from_archive "$MC_ARCHIVE" "mcli" "$MINIO_BIN_DIR/mcli"

echo "Installed pgsty/minio assets for ${MINIO_ARCHIVE_OS}_${MINIO_ARCHIVE_ARCH}"
"$MINIO_BIN_DIR/minio" --version
"$MINIO_BIN_DIR/mcli" --version

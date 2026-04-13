# LanceDB Local Build Onboard

This note records a full local onboard path for building the Python version of
LanceDB from source on a clean Debian 13 / WSL2 machine without `sudo`.

In the commands below, replace `<project-root>` with the local directory that
contains this document, the `onboard/` helpers, and the `lancedb/` checkout.

## Goal

Get the local source tree built and usable enough to:

1. verify that the Python / Rust / `protoc` toolchain is ready
2. compile `lancedb` from source with multi-core builds
3. run a small local vector-search smoke test

## Environment Used

- OS: Debian 13 (WSL2)
- Shell: `bash`
- CPU parallelism: `12` jobs from `nproc`
- No preinstalled `python`, `cargo`, `rustc`, or `protoc`
- `uv` was already available

## User-Local Dependency Install

### Optional: configure mirrors before installing

If your network to GitHub, PyPI, or `crates.io` is unstable, copy the mirror
template first:

```bash
cd <project-root>
cp onboard/mirror.env.example onboard/mirror.env
```

If you want a ready-to-use TUNA preset, use this instead:

```bash
cd <project-root>
cp onboard/mirror.env.tuna onboard/mirror.env
```

`onboard/env.sh` will load `onboard/mirror.env` automatically. The template
already includes TUNA examples for PyPI and Rustup, and keeps Python-download
and `protoc` mirrors as explicit opt-ins.

If you also want Cargo to use TUNA's sparse index, copy the example into your
Cargo config:

```bash
mkdir -p "${CARGO_HOME:-$HOME/.cargo}"
cp onboard/cargo.tuna.config.toml.example "${CARGO_HOME:-$HOME/.cargo}/config.toml"
```

### One-command prerequisite install

After optional mirror configuration, install Python, Rust, and `protoc` with:

```bash
cd <project-root>
bash onboard/install_prereqs.sh
```

This script respects the mirror-related environment variables from
`onboard/mirror.env`, including:

- `PIP_INDEX_URL`
- `UV_DEFAULT_INDEX`
- `UV_PYTHON_INSTALL_MIRROR`
- `RUSTUP_DIST_SERVER`
- `RUSTUP_UPDATE_ROOT`
- `PROTOC_DOWNLOAD_URL`

### 1. Install Python 3.12 with uv

```bash
uv python install 3.12
```

### 2. Install Rust 1.94.0 with rustup

This repo pins the Rust toolchain in `rust-toolchain.toml`.

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
  sh -s -- -y --default-toolchain 1.94.0 --profile minimal
```

### 3. Install `protoc` in `$HOME/.local`

```bash
PROTOC_VERSION=34.1
INSTALL_DIR="$HOME/.local/opt/protoc-$PROTOC_VERSION"
BIN_DIR="$HOME/.local/bin"
PY_BIN="$(uv python find 3.12)"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
TMP_ZIP="$(mktemp /tmp/protoc.XXXXXX.zip)"
curl -L \
  "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip" \
  -o "$TMP_ZIP"
"$PY_BIN" -m zipfile -e "$TMP_ZIP" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/bin/protoc"
ln -sf "$INSTALL_DIR/bin/protoc" "$BIN_DIR/protoc"
rm -f "$TMP_ZIP"
protoc --version
```

## Important WSL / uv Notes

- Prefer the real interpreter from `uv python find 3.12`.
- Do not rely on `~/.local/bin/python3.12` for `venv` creation on this setup.
  That shim worked for direct execution, but the child venv ended up with
  `sys.base_prefix=/install` and `ensurepip` failed.
- Run temporary venv or smoke-test data under `/tmp`, not a Windows-mounted
  path.
- After extracting the official `protoc` zip with Python's `zipfile` module,
  restore execute permission manually with `chmod +x`.

## Root-Level Helper Scripts

The following helper files live at the project root so the `lancedb` checkout
stays clean:

- `onboard/env.sh`
- `onboard/install_prereqs.sh`
- `onboard/verify_toolchain.sh`
- `onboard/build_lancedb.sh`
- `onboard/mirror.env.example`
- `onboard/mirror.env.tuna`
- `onboard/cargo.tuna.config.toml.example`
- `onboard/minio_common.sh`
- `onboard/minio.env.example`
- `onboard/install_pgsty_minio.sh`
- `onboard/start_pgsty_minio.sh`
- `onboard/stop_pgsty_minio.sh`
- `onboard/setup_pgsty_minio.sh`
- `onboard/python_env_check.py`
- `onboard/rust_native_check/`
- `onboard/rust_protoc_check/`
- `onboard/lancedb_smoke_test.py`
- `onboard/lancedb_s3_smoke_test.py`

## Verify Build Dependencies Before Compiling LanceDB

Source the helper environment and run the toolchain smoke tests:

```bash
cd <project-root>
source onboard/env.sh
bash onboard/verify_toolchain.sh
```

What this validates:

- Python version, SSL, SQLite, and `venv` creation
- Rust compilation and linker / C toolchain health
- `protoc` integration through a tiny `prost-build` example

## Build LanceDB Python Locally

### One-command build

```bash
cd <project-root>
bash onboard/build_lancedb.sh
```

### Equivalent manual steps

Create a venv with the real uv-managed Python:

```bash
cd <project-root>
source onboard/env.sh
"$PYTHON_BIN" -m venv lancedb/python/.venv
```

Install `maturin`:

```bash
lancedb/python/.venv/bin/pip install -U pip maturin
```

Compile and install the local source tree into that venv with multi-core builds:

```bash
source onboard/env.sh
cd lancedb/python
. .venv/bin/activate
maturin develop -j "$CARGO_BUILD_JOBS"
```

If `PIP_EXTRA_INDEX_URL` or `UV_INDEX` is already set in `onboard/mirror.env`,
keep it. The helper build script will append the required Fury indexes
automatically.

On the first run in this environment, `maturin develop` completed successfully
in about `6m 37s`.

## Run the Minimal LanceDB Smoke Test

```bash
cd <project-root>
source onboard/env.sh
lancedb/python/.venv/bin/python -c "import lancedb; print(lancedb.__version__)"
lancedb/python/.venv/bin/python onboard/lancedb_smoke_test.py
```

The smoke test creates a temporary local DB, inserts three rows, runs a vector
search, and checks that the nearest hit is `"bar"`.

## Optional: Local S3 via `pgsty/minio`

If you want LanceDB to use an S3-compatible object store locally, this workspace
also includes helper scripts for the community-maintained `pgsty/minio` fork and
the companion `pgsty/mc` client fork.

### Prepare local MinIO config

```bash
cd <project-root>
cp onboard/minio.env.example onboard/minio.env
```

Default values in `onboard/minio.env.example`:

- endpoint: `http://127.0.0.1:9000`
- console: `http://127.0.0.1:9001`
- access key: `ACCESSKEY`
- secret key: `SECRETKEY`
- region: `us-east-1`
- bucket: `lancedb-dev`

### Download the fork binaries and start the service

```bash
cd <project-root>
bash onboard/setup_pgsty_minio.sh
```

This script:

- downloads the latest GitHub release assets from `pgsty/minio`
- downloads the latest GitHub release assets from `pgsty/mc`
- installs both binaries under `local/bin/`
- starts a single-node MinIO server with data under `local/minio/data`
- creates the default bucket from `onboard/minio.env`

Runtime artifacts are kept under `local/` and ignored by the root `.gitignore`.

### Verify LanceDB can use S3 storage against local MinIO

```bash
cd <project-root>
source onboard/minio.env
lancedb/python/.venv/bin/python onboard/lancedb_s3_smoke_test.py
```

The S3 smoke test:

- connects to `s3://$MINIO_BUCKET/...` with LanceDB `storage_options`
- creates a table
- inserts rows
- runs a vector search
- drops the temporary database prefix after validation

### Stop the local MinIO service

```bash
cd <project-root>
bash onboard/stop_pgsty_minio.sh
```

## Developer Quick Reference

### Enter the local dev environment

```bash
cd <project-root>
source onboard/env.sh
. lancedb/python/.venv/bin/activate
```

### Confirm you are using the local editable install

```bash
python -c "import lancedb; print(lancedb.__version__); print(lancedb.__file__)"
```

`lancedb.__file__` should point back into this repo, for example under
`python/python/lancedb`.

### When do you need to rebuild?

- Pure Python changes under `python/python/lancedb/` are usually picked up
  immediately by the editable install.
- Rust changes under `python/src/` or `rust/lancedb/` require a rebuild.
- If unsure, just re-run the one-command build:

```bash
bash onboard/build_lancedb.sh
```

### Install the full contributor dependency set

The lightweight onboard build installs runtime dependencies only. If you want
to run the Python test suite and repo checks the same way maintainers do, use:

```bash
cd <project-root>
source onboard/env.sh
cd lancedb/python
. .venv/bin/activate
maturin develop -j "$CARGO_BUILD_JOBS" --extras tests,dev,embeddings
```

### Common test commands

Run the default Python test selection from the repo Makefile:

```bash
cd <project-root>/lancedb/python
. .venv/bin/activate
pytest python/tests -vv --durations=10 -m "not slow and not s3_test"
```

Run one file:

```bash
pytest -vv python/tests/test_db.py
```

Run one test:

```bash
pytest -vv python/tests/test_db.py::test_basic
```

### Common formatting and lint commands

```bash
cd <project-root>/lancedb/python
. .venv/bin/activate
cargo fmt
ruff format python
cargo clippy
ruff check python
```

### Fast sanity checks during development

```bash
cd <project-root>
source onboard/env.sh
lancedb/python/.venv/bin/python -c "import lancedb; print(lancedb.__version__)"
lancedb/python/.venv/bin/python onboard/lancedb_smoke_test.py
```

## If Something Fails

- Downloads are slow or flaky:
  Copy `onboard/mirror.env.example` to `onboard/mirror.env`, choose a closer
  PyPI / Rustup mirror, and optionally apply
  `onboard/cargo.tuna.config.toml.example`.
- `python-env-check` fails while creating a venv:
  Use the interpreter from `uv python find 3.12`, not the shim in
  `~/.local/bin/python3.12`.
- `protoc: Permission denied`:
  Re-run `chmod +x "$HOME/.local/opt/protoc-<version>/bin/protoc"`.
- Cargo says a helper crate "believes it's in a workspace":
  Keep helper crates standalone by leaving an empty `[workspace]` table in
  their `Cargo.toml`.
- LanceDB compile is slower than expected:
  Confirm `echo "$CARGO_BUILD_JOBS"` matches `nproc`.

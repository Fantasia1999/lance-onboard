# LanceDB Local Build Onboard

This document matches the helper scripts in `onboard/` and is intended to help
a beginner bring up a local LanceDB development environment from scratch on
regular Linux or WSL2, without depending on a distro-specific package manager.

It covers:

- a local LanceDB source build environment
- a Python-editable local install
- an optional local MinIO-based S3-compatible environment

This guide assumes your workspace contains:

- this repository
- a local `lancedb` source checkout

The simplest layout looks like this:

```text
<project-root>/
├── LANCEDB_LOCAL_ONBOARD.md
├── README.md
├── onboard/
└── lancedb/
```

If your `lancedb` checkout is somewhere else, set
`LANCEDB_REPO=/absolute/path/to/lancedb` in `onboard/mirror.env`.

## Scope

These scripts are primarily aimed at:

- native Linux
- Linux distributions running inside WSL2

The design goal is "user-local installs, minimal distro assumptions". The
helpers do not call `apt`, `yum`, `dnf`, `pacman`, or another distro package
manager directly.

They still assume the machine already has a few basic commands:

- `bash`
- `curl`
- `tar`
- common coreutils such as `mkdir`, `find`, `install`, and `mktemp`

If a machine is missing even those, that is outside what a distro-agnostic
bootstrap script can realistically cover.

## Goal

The goal is to get all of the following working:

1. check and install Python / Rust / `protoc`
2. build the Python package from the local LanceDB source tree
3. run a local vector-search smoke test
4. optionally start local MinIO and validate LanceDB against S3-compatible
   storage

## Main Local Build Flow

### 1. Enter the project directory

```bash
cd <project-root>
```

### 2. Optional: configure mirrors

Mirrors are not required by default. Only enable them if access to GitHub,
PyPI, or `crates.io` is slow or unreliable.

General template:

```bash
cp onboard/mirror.env.example onboard/mirror.env
```

TUNA preset:

```bash
cp onboard/mirror.env.tuna onboard/mirror.env
```

If you also want Cargo to use TUNA's sparse index:

```bash
mkdir -p "${CARGO_HOME:-$HOME/.cargo}"
cp onboard/cargo.tuna.config.toml.example "${CARGO_HOME:-$HOME/.cargo}/config.toml"
```

### 3. Load the helper environment

```bash
source onboard/env.sh
```

That script does a few important things:

- loads `onboard/mirror.env` automatically if it exists
- points `LANCEDB_REPO` at `./lancedb` by default
- prepends `~/.local/bin` and `~/.cargo/bin` to `PATH`
- tries to discover `PYTHON_BIN`
- exports `CARGO_BUILD_JOBS`

### 4. Install prerequisites

```bash
bash onboard/install_prereqs.sh
```

This script is idempotent. If a tool already meets the minimum requirement, it
is skipped.

Default behavior:

| Tool | Minimum | Default behavior |
|---|---|---|
| Python | >= 3.10 | If missing, bootstrap `uv` first, then install Python 3.12 with `uv` |
| Rust | >= 1.85.0 | If `lancedb/rust-toolchain.toml` or `rust-toolchain` exists, install that exact Rust toolchain; otherwise install/update `stable` via `rustup` |
| protoc | >= 34.1 | Download the official zip into `~/.local/opt` and link it into `~/.local/bin` |

The script tries not to require a preinstalled Python. In other words, if the
machine has `curl` but no `python3`, it can still bootstrap `uv` first and then
install Python through `uv`.

The script respects these variables from `onboard/mirror.env`:

- `LANCEDB_REPO`
- `PIP_INDEX_URL`
- `PIP_EXTRA_INDEX_URL`
- `UV_DEFAULT_INDEX`
- `UV_PYTHON_INSTALL_MIRROR`
- `RUSTUP_DIST_SERVER`
- `RUSTUP_UPDATE_ROOT`
- `RUSTUP_INIT_URL`
- `PROTOC_DOWNLOAD_URL`
- `CURL_RETRY_COUNT`
- `PIP_INSTALL_RETRIES`
- `PIP_INSTALL_TIMEOUT`

It also supports these overrides:

- `PYTHON_VERSION`
- `PYTHON_MIN_VERSION`
- `RUST_MIN_VERSION`
- `RUST_TOOLCHAIN`
- `PROTOC_VERSION`
- `UV_INSTALLER_URL`

### 5. Verify the toolchain

```bash
bash onboard/verify_toolchain.sh
```

This validates:

- Python version, SSL, SQLite, and `venv` creation
- Rust compilation plus linker / native toolchain health
- `protoc` integration through a tiny `prost-build` example

### 6. Build LanceDB

```bash
bash onboard/build_lancedb.sh
```

This script will:

- create `lancedb/python/.venv` using `PYTHON_BIN`
- install `pip` and `maturin`
- automatically append the required Lance Fury indexes
- run `maturin develop -j "$CARGO_BUILD_JOBS"` in `lancedb/python`

If the `lancedb` repo is not where the script expects it, it will stop and tell
you to set `LANCEDB_REPO`.

### 7. Run the local smoke test

```bash
lancedb/python/.venv/bin/python -c "import lancedb; print(lancedb.__version__)"
lancedb/python/.venv/bin/python onboard/lancedb_smoke_test.py
```

The smoke test creates a temporary database under `/tmp`, inserts three rows,
runs a vector search, and verifies that the nearest result is correct.

## Optional: Local MinIO (S3-Compatible)

### 1. Copy the config template

```bash
cp onboard/minio.env.example onboard/minio.env
```

The defaults include:

- `MINIO_HOST=127.0.0.1`
- `MINIO_PORT=9000`
- `MINIO_CONSOLE_PORT=9001`
- `MINIO_BUCKET=lancedb-dev`

This file also exports the AWS-style variables that the S3 smoke test uses:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `AWS_ENDPOINT`
- `AWS_ENDPOINT_URL`

So in the normal case you only need `source onboard/minio.env`; you do not need
to construct the AWS variables again by hand.

### 2. Download and start MinIO

```bash
bash onboard/setup_pgsty_minio.sh
```

This is equivalent to:

```bash
bash onboard/install_pgsty_minio.sh
bash onboard/start_pgsty_minio.sh
```

The install script automatically selects the matching release asset for the
current machine:

- `linux_amd64`
- `linux_arm64`

By default it downloads the latest GitHub release `tar.gz` assets from
`pgsty/minio` and `pgsty/mc`, then verifies them against the published checksum
file.

Runtime files are stored under:

```text
local/
├── bin/
├── downloads/
├── mc/
└── minio/
    ├── data/
    ├── logs/minio.log
    └── run/minio.pid
```

### 3. Verify LanceDB against local S3-compatible storage

```bash
source onboard/minio.env
lancedb/python/.venv/bin/python onboard/lancedb_s3_smoke_test.py
```

The S3 smoke test:

- connects to `s3://$MINIO_BUCKET/...`
- creates a temporary table
- inserts test rows
- runs a vector search
- drops the temporary database prefix on success

### 4. Stop MinIO

```bash
bash onboard/stop_pgsty_minio.sh
```

The stop script sends `TERM` first and falls back to `KILL` if needed, so it
does not leave behind a removed pid file while the process is still alive.

## WSL Recommendations

- Prefer keeping the repo on the Linux filesystem inside WSL, for example
  `~/workspace/...`, instead of building from `/mnt/c/...`.
- `python_env_check.py` and the smoke tests intentionally use `/tmp` for
  temporary files to avoid common Windows-mounted filesystem issues.
- If your WSL setup has multiple Python shims, prefer the real interpreter found
  by `uv python find`.

## Common Developer Commands

Enter the local development environment:

```bash
cd <project-root>
source onboard/env.sh
. lancedb/python/.venv/bin/activate
```

Confirm that you are importing the editable local install:

```bash
python -c "import lancedb; print(lancedb.__version__); print(lancedb.__file__)"
```

Rebuild:

```bash
bash onboard/build_lancedb.sh
```

Install a fuller contributor dependency set:

```bash
cd <project-root>/lancedb/python
. .venv/bin/activate
maturin develop -j "$CARGO_BUILD_JOBS" --extras tests,dev,embeddings
```

Common test commands:

```bash
pytest python/tests -vv --durations=10 -m "not slow and not s3_test"
pytest -vv python/tests/test_db.py
pytest -vv python/tests/test_db.py::test_basic
```

## Troubleshooting

### `install_prereqs.sh` fails immediately

First confirm the machine already has:

- `bash`
- `curl`
- `tar`

If any of those are missing, the bootstrap flow cannot continue.

You also need a system C toolchain once Rust starts compiling native crates.
On Debian/Ubuntu/WSL, install it with:

```bash
sudo apt update
sudo apt install -y build-essential
```

On Fedora/RHEL/CentOS/Rocky/AlmaLinux, install it with:

```bash
sudo dnf install -y gcc gcc-c++ make
```

On older RHEL/CentOS releases without `dnf`, use:

```bash
sudo yum install -y gcc gcc-c++ make
```

### `uv` or Python was installed but the current shell still cannot find it

Run:

```bash
source onboard/env.sh
```

`env.sh` now prepends `~/.local/bin` automatically, so you usually do not need
to edit your shell profile just to continue onboarding.

### `verify_toolchain.sh` still picks an older Python

First clear any shell overrides, then reload the helper environment:

```bash
unset PYTHON_BIN PYO3_PYTHON
source onboard/env.sh
echo "$PYTHON_BIN"
bash onboard/verify_toolchain.sh
```

If `echo "$PYTHON_BIN"` still points at `/usr/bin/python3`, your shell profile
is likely exporting an old interpreter path somewhere else.

### `verify_toolchain.sh` fails with `linker 'cc' not found`

Rust can be installed entirely under your home directory, but native crates
still need a system C compiler and linker.

On Debian/Ubuntu/WSL, run:

```bash
sudo apt update
sudo apt install -y build-essential
```

On Fedora/RHEL/CentOS/Rocky/AlmaLinux, run:

```bash
sudo dnf install -y gcc gcc-c++ make
```

On older RHEL/CentOS releases without `dnf`, use:

```bash
sudo yum install -y gcc gcc-c++ make
```

Then retry:

```bash
bash onboard/verify_toolchain.sh
```

### `protoc: Permission denied`

Restore execute permission:

```bash
chmod +x "$HOME/.local/opt/protoc-<version>/bin/protoc"
```

### MinIO fails to start

Check the log first:

```bash
tail -n 50 local/minio/logs/minio.log
```

Then verify:

- `MINIO_PORT` / `MINIO_CONSOLE_PORT` are not already in use
- the credentials in `onboard/minio.env` are what you expect
- the machine can reach GitHub releases

### The S3 smoke test says AWS variables are missing

Run:

```bash
source onboard/minio.env
```

Do not only start MinIO; also load the environment file before the S3 smoke
test.

### Compilation is slower than expected

Check the parallel build setting:

```bash
source onboard/env.sh
echo "$CARGO_BUILD_JOBS"
```

If needed, you can override it manually:

```bash
export CARGO_BUILD_JOBS=4
```

# Lance Onboard

This repository keeps local onboarding scripts and notes outside the upstream
`lancedb` checkout, with the goal of helping a beginner bring up a usable
`LanceDB + MinIO` environment from scratch on Linux or WSL.

## Before You Start

These scripts build against a local `lancedb` source checkout. They do not
clone `lancedb` for you automatically.

Before running anything in `onboard/`, choose one of these layouts:

### Option A: clone `lancedb` into this repo

Recommended for first-time setup:

```bash
cd /path/to/lance-onboard
git clone https://github.com/lancedb/lancedb.git ./lancedb
```

### Option B: keep `lancedb` somewhere else and point the scripts at it

If you already have a local `lancedb` checkout elsewhere, set
`LANCEDB_REPO` before running `source onboard/env.sh`:

```bash
cp onboard/mirror.env.example onboard/mirror.env
```

Then edit `onboard/mirror.env` and set:

```bash
export LANCEDB_REPO="/absolute/path/to/lancedb"
```

## Layout

- `lancedb/`: recommended default location for the local `lancedb` checkout
  when you clone it inside this repository
- `onboard/`: helper scripts for environment setup, validation, local builds,
  MinIO setup, and smoke tests
- `LANCEDB_LOCAL_SETUP.md`: the longer step-by-step guide with troubleshooting
- `local/`: runtime artifacts created by the helper scripts and ignored by Git

Supported workspace layouts look like this:

```text
/path/to/lance-onboard/
├── README.md
├── LANCEDB_LOCAL_SETUP.md
├── onboard/
├── local/
└── lancedb/
```

Or:

```text
/path/to/lance-onboard/
├── README.md
├── LANCEDB_LOCAL_SETUP.md
├── onboard/
└── local/

/some/other/place/lancedb/
```

In the second case, set this in `onboard/mirror.env`:

```bash
export LANCEDB_REPO="/absolute/path/to/lancedb"
```

## Supported Environments

The scripts are primarily meant for:

- native Linux
- Linux running inside WSL2

The workflow tries hard not to depend on `apt`, `yum`, `dnf`, or another
distro-specific package manager. By default it installs Python, Rust, `protoc`,
and MinIO-related tooling into user-local directories.

When a local `lancedb` checkout includes `rust-toolchain.toml` or
`rust-toolchain`, the Rust bootstrap flow uses that toolchain only when Rust is
missing or below the minimum version. If you already have a new enough Rust
toolchain, it leaves your existing install alone.

`onboard/build_lancedb.sh` also prefers your current Rust toolchain when it
already meets the repo's minimum supported Rust version, instead of forcing the
repo-pinned toolchain for that build.

It still assumes the machine already has a few base utilities:

- `bash`
- `curl`
- `tar`
- common coreutils such as `mkdir`, `mktemp`, `find`, and `install`
- a system C toolchain available as `cc` when compiling Rust native crates or the Python extension

On Debian/Ubuntu/WSL, install the C toolchain with:

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

## Quick Start

From the project root, after you have either cloned `lancedb` into `./lancedb`
or set `LANCEDB_REPO` to an existing checkout:

```bash
cd /path/to/lance-onboard
source onboard/env.sh
bash onboard/install_prereqs.sh
bash onboard/verify_toolchain.sh
bash onboard/build_lancedb.sh
```

Then run the local smoke test:

```bash
"$LANCEDB_REPO/python/.venv/bin/python" onboard/lancedb_smoke_test.py
```

## Optional: Configure Mirrors

Mirrors are optional. If GitHub, PyPI, or `crates.io` is slow or unstable in
your region, copy the template first:

```bash
cp onboard/mirror.env.example onboard/mirror.env
```

If you want the ready-made TUNA preset instead:

```bash
cp onboard/mirror.env.tuna onboard/mirror.env
```

`source onboard/env.sh` will automatically load `onboard/mirror.env`.

## Optional: Start Local MinIO (S3-Compatible)

```bash
cp onboard/minio.env.example onboard/minio.env
bash onboard/setup_pgsty_minio.sh
source onboard/minio.env
"$LANCEDB_REPO/python/.venv/bin/python" onboard/lancedb_s3_smoke_test.py
```

The MinIO helpers automatically pick the matching Linux release asset for the
current architecture and store binaries, logs, and runtime data under `local/`.

Stop the local MinIO service with:

```bash
bash onboard/stop_pgsty_minio.sh
```

## More Detail

For the full zero-to-working flow, WSL notes, and troubleshooting, see
[`LANCEDB_LOCAL_SETUP.md`](/home/wcl/workspace/dev/lance-onboard/LANCEDB_LOCAL_SETUP.md).

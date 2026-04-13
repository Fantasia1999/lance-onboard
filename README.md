# Lance Onboard

This workspace keeps the upstream `lancedb` source checkout clean while storing
local onboarding notes and helper scripts at the project root.

## Layout

- `lancedb/`: local checkout of the LanceDB source repository
- `LANCEDB_LOCAL_ONBOARD.md`: step-by-step local build and onboarding notes
- `onboard/`: helper scripts for environment setup, dependency checks, local
  build, and smoke tests

## Common Commands

Run these from the project root:

```bash
cp onboard/mirror.env.tuna onboard/mirror.env  # optional
source onboard/env.sh
bash onboard/install_prereqs.sh
bash onboard/verify_toolchain.sh
bash onboard/build_lancedb.sh
```

## Optional Local S3

To prepare a local S3-compatible object store using the `pgsty/minio` and
`pgsty/mc` forks:

```bash
cp onboard/minio.env.example onboard/minio.env
bash onboard/setup_pgsty_minio.sh
source onboard/minio.env
lancedb/python/.venv/bin/python onboard/lancedb_s3_smoke_test.py
```

Stop the local MinIO server with:

```bash
bash onboard/stop_pgsty_minio.sh
```

For the full workflow and troubleshooting notes, see
`LANCEDB_LOCAL_ONBOARD.md`.

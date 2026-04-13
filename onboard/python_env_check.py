from __future__ import annotations

import sqlite3
import ssl
import sys
import tempfile
import venv
from pathlib import Path


def main() -> None:
    version = sys.version_info
    if version < (3, 10):
        raise SystemExit(f"Python >= 3.10 is required, found {sys.version}")

    print(f"python-env-check: interpreter={sys.executable}")
    print(f"python-env-check: version={sys.version.split()[0]}")
    print(f"python-env-check: openssl={ssl.OPENSSL_VERSION}")
    print(f"python-env-check: sqlite={sqlite3.sqlite_version}")

    # On WSL, the default temp dir may point at a Windows-mounted path.
    # Creating venvs there can fail, so keep the smoke test on the Linux filesystem.
    with tempfile.TemporaryDirectory(prefix="lancedb-venv-check-", dir="/tmp") as tmp_dir:
        venv_dir = Path(tmp_dir) / "venv"
        venv.EnvBuilder(with_pip=True).create(venv_dir)
        candidates = [venv_dir / "bin" / "python", venv_dir / "bin" / "python3"]
        venv_python = next((path for path in candidates if path.exists()), None)
        if venv_python is None:
            raise SystemExit("python-env-check: failed to create a virtualenv with Python")
        print(f"python-env-check: venv_python={venv_python}")

    print("python-env-check: ok")


if __name__ == "__main__":
    main()

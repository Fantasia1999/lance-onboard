from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

import lancedb


def main() -> None:
    db_dir = Path(tempfile.mkdtemp(prefix="lancedb-smoke-", dir="/tmp"))
    print(f"lancedb-smoke-test: db_dir={db_dir}")

    try:
        db = lancedb.connect(db_dir)
        table = db.create_table(
            "items",
            data=[
                {"vector": [3.1, 4.1], "item": "foo", "price": 10.0},
                {"vector": [5.9, 26.5], "item": "bar", "price": 20.0},
                {"vector": [10.0, 10.0], "item": "baz", "price": 30.0},
            ],
        )

        results = table.search([100.0, 100.0]).limit(2).to_list()
        print("lancedb-smoke-test: results=" + json.dumps(results, ensure_ascii=True))

        if len(results) != 2:
            raise SystemExit(f"expected 2 results, got {len(results)}")
        if results[0]["item"] != "bar":
            raise SystemExit(f"expected nearest item to be 'bar', got {results[0]['item']}")

        print("lancedb-smoke-test: ok")
    finally:
        shutil.rmtree(db_dir, ignore_errors=True)


if __name__ == "__main__":
    main()

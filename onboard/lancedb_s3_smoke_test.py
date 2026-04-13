from __future__ import annotations

import os
import uuid

import lancedb


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"missing required environment variable: {name}")
    return value


def main() -> None:
    bucket = os.environ.get("MINIO_BUCKET", "lancedb-dev")
    endpoint = (
        os.environ.get("AWS_ENDPOINT")
        or os.environ.get("AWS_ENDPOINT_URL")
        or os.environ.get("MINIO_ENDPOINT")
    )
    if not endpoint:
        raise SystemExit("missing AWS_ENDPOINT / AWS_ENDPOINT_URL / MINIO_ENDPOINT")

    storage_options = {
        "allow_http": "true",
        "aws_access_key_id": required_env("AWS_ACCESS_KEY_ID"),
        "aws_secret_access_key": required_env("AWS_SECRET_ACCESS_KEY"),
        "aws_endpoint": endpoint,
        "aws_region": os.environ.get("AWS_REGION", os.environ.get("MINIO_REGION", "us-east-1")),
    }

    prefix = f"lancedb-s3-smoke-{uuid.uuid4().hex[:8]}"
    uri = f"s3://{bucket}/{prefix}"
    print(f"lancedb-s3-smoke-test: uri={uri}")

    db = lancedb.connect(uri, storage_options=storage_options)
    table = db.create_table(
        "items",
        data=[
            {"vector": [3.1, 4.1], "item": "foo", "price": 10.0},
            {"vector": [5.9, 26.5], "item": "bar", "price": 20.0},
            {"vector": [10.0, 10.0], "item": "baz", "price": 30.0},
        ],
        mode="overwrite",
    )

    results = table.search([100.0, 100.0]).limit(2).to_list()
    print(f"lancedb-s3-smoke-test: results={results}")

    if len(results) != 2:
        raise SystemExit(f"expected 2 results, got {len(results)}")
    if results[0]["item"] != "bar":
        raise SystemExit(f"expected nearest item to be 'bar', got {results[0]['item']}")

    db.drop_database()
    print("lancedb-s3-smoke-test: ok")


if __name__ == "__main__":
    main()

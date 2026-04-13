from __future__ import annotations

import os
import uuid

import lancedb


def first_env(*names: str) -> str | None:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return None


def required_any_env(*names: str) -> str:
    value = first_env(*names)
    if value:
        return value
    joined = " / ".join(names)
    raise SystemExit(f"missing required environment variable: {joined}")


def main() -> None:
    bucket = os.environ.get("MINIO_BUCKET", "lancedb-dev")
    endpoint = first_env("AWS_ENDPOINT", "AWS_ENDPOINT_URL", "MINIO_ENDPOINT")
    if not endpoint:
        host = os.environ.get("MINIO_HOST", "127.0.0.1")
        port = os.environ.get("MINIO_PORT", "9000")
        endpoint = f"http://{host}:{port}"

    storage_options = {
        "allow_http": os.environ.get("AWS_ALLOW_HTTP", "true"),
        "aws_access_key_id": required_any_env("AWS_ACCESS_KEY_ID", "MINIO_ROOT_USER"),
        "aws_secret_access_key": required_any_env(
            "AWS_SECRET_ACCESS_KEY", "MINIO_ROOT_PASSWORD"
        ),
        "aws_endpoint": endpoint,
        "aws_region": first_env("AWS_REGION", "MINIO_REGION") or "us-east-1",
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

    db.drop_all_tables()
    print("lancedb-s3-smoke-test: ok")


if __name__ == "__main__":
    main()

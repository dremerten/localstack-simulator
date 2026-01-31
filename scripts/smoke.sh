#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$root_dir"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

echo "Running AWS CLI smoke test inside iac-sandbox..."
docker compose exec -T iac-sandbox /bin/bash -lc '
  aws --endpoint-url "$LOCALSTACK_ENDPOINT" sts get-caller-identity >/dev/null
  aws --endpoint-url "$LOCALSTACK_ENDPOINT" s3api list-buckets >/dev/null
  echo "iac-sandbox awscli: ok"
'

echo "OK"

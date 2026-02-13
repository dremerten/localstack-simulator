#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
custom_file="$root_dir/.custom_secrets.txt"

if [ -f "$custom_file" ]; then
  set -a
  . "$custom_file"
  set +a
fi

: "${AWS_ACCESS_KEY_ID:=$(openssl rand -hex 16)}"
: "${AWS_SECRET_ACCESS_KEY:=$(openssl rand -hex 16)}"
: "${DB_USERNAME:=$(openssl rand -hex 16)}"
: "${DB_PASSWORD:=$(openssl rand -hex 16)}"

if [ -z "${DOCKERHUB_USERNAME:-}" ] || [ -z "${DOCKERHUB_TOKEN:-}" ]; then
  echo "Set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN in .custom_secrets.txt or environment" >&2
  exit 1
fi
APP_DOMAIN="${APP_DOMAIN:-iac-sandbox-staging.dremer10.com}"

SANDBOX_IMAGE="${SANDBOX_IMAGE:-${DOCKER_IMAGE:-}}"
if [ -z "${SANDBOX_IMAGE:-}" ]; then
  echo "Set SANDBOX_IMAGE (or DOCKER_IMAGE) in .custom_secrets.txt or environment" >&2
  exit 1
fi

APP_NAMESPACE="${APP_NAMESPACE:-iac-sandbox-staging}"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export DB_USERNAME
export DB_PASSWORD
export APP_DOMAIN
export APP_NAMESPACE
export SANDBOX_IMAGE

auth_b64="$(printf '%s:%s' "$DOCKERHUB_USERNAME" "$DOCKERHUB_TOKEN" | base64 | tr -d '\n')"
DOCKER_CONFIG_JSON="$(printf '{\"auths\":{\"https://index.docker.io/v1/\":{\"username\":\"%s\",\"password\":\"%s\",\"email\":\"%s\",\"auth\":\"%s\"}}}' \
  "$DOCKERHUB_USERNAME" "$DOCKERHUB_TOKEN" "${DOCKERHUB_EMAIL:-}" "$auth_b64")"
export DOCKER_CONFIG_JSON

envsubst < "$root_dir/k8s/staging/apply.yaml" | kubectl apply -f -

#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
custom_file="$root_dir/.custom_secrets.txt"

if [ -f "$custom_file" ]; then
  set -a
  . "$custom_file"
  set +a
fi

: "${DOCKERHUB_USERNAME:=${DOCKERHUB_USERNAME:-}}"
: "${DOCKERHUB_TOKEN:=${DOCKERHUB_TOKEN:-}}"
: "${DOCKERHUB_EMAIL:=${DOCKERHUB_EMAIL:-}}"
SANDBOX_IMAGE="${SANDBOX_IMAGE:-${DOCKER_IMAGE:-}}"

if [ -z "$DOCKERHUB_USERNAME" ] || [ -z "$DOCKERHUB_TOKEN" ]; then
  echo "Set DOCKERHUB_USERNAME and DOCKERHUB_TOKEN in .custom_secrets.txt or env" >&2
  exit 1
fi
if [ -z "$SANDBOX_IMAGE" ]; then
  echo "Set SANDBOX_IMAGE (or DOCKER_IMAGE) in .custom_secrets.txt or env" >&2
  exit 1
fi

cd "$root_dir"

echo "Logging in to Docker Hub..."
echo "$DOCKERHUB_TOKEN" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin

if [ -n "$DOCKERHUB_EMAIL" ]; then
  echo "Using Docker Hub email: $DOCKERHUB_EMAIL"
fi

echo "Building image $SANDBOX_IMAGE..."
docker build -t "$SANDBOX_IMAGE" .

echo "Pushing image $SANDBOX_IMAGE..."
docker push "$SANDBOX_IMAGE"

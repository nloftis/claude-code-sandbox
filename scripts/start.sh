#!/usr/bin/env bash
# Starts (or resumes) a persistent, named container in the background.
# Use attach.sh to get a shell inside it, stop.sh to tear it down.
#
# Auth: set CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token` on the
# host, recommended) or ANTHROPIC_API_KEY in .env. Either works.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_NAME="claude-code-sandbox"
CONTAINER_NAME="claude-sandbox"

if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Container '${CONTAINER_NAME}' already exists. Starting it..."
  podman start "${CONTAINER_NAME}"
else
  podman build \
    --build-arg UID="$(id -u)" \
    --build-arg GID="$(id -g)" \
    -t "${IMAGE_NAME}" \
    -f ./podman/Containerfile \
    ./podman
  podman run -d \
    --userns=keep-id \
    --name "${CONTAINER_NAME}" \
    --env-file .env \
    -v "$(pwd)/workspace:/home/claude/workspace" \
    "${IMAGE_NAME}" \
    tail -f /dev/null
fi

echo "Container '${CONTAINER_NAME}' is up. Run ./scripts/attach.sh to get a shell."
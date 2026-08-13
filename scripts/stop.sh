#!/usr/bin/env bash
# Stops and removes the persistent container. Anything not saved under
# ../workspace (which is bind-mounted, so it's safe) is lost.
set -euo pipefail

CONTAINER_NAME="claude-sandbox"

docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo "Container '${CONTAINER_NAME}' stopped and removed."

#!/usr/bin/env bash
# Opens an interactive shell in the already-running persistent container.
# Run start.sh first if the container isn't up yet.
#
# Once inside, run: claude --dangerously-skip-permissions
set -euo pipefail

CONTAINER_NAME="claude-sandbox"

podman exec -it "${CONTAINER_NAME}" bash
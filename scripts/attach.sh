#!/usr/bin/env bash
# Opens an interactive shell in whichever sandbox container is currently
# running, whether it was started via start.sh (persistent, --name
# claude-sandbox) or run.sh (ephemeral, --name claude-sandbox-ephemeral).
# Run one of those first if no container is up yet.
#
# Once inside, run: claude --dangerously-skip-permissions
set -euo pipefail

IMAGE_NAME="claude-code-sandbox"

mapfile -t RUNNING < <(podman ps \
  --filter "ancestor=localhost/${IMAGE_NAME}:latest" \
  --format "{{.Names}}")

if [ "${#RUNNING[@]}" -eq 0 ]; then
  echo "Error: no running ${IMAGE_NAME} container found." >&2
  echo "Start one first with ./scripts/start.sh (persistent) or ./scripts/run.sh (ephemeral)." >&2
  exit 1
fi

if [ "${#RUNNING[@]}" -gt 1 ]; then
  echo "Error: multiple ${IMAGE_NAME} containers are running, refusing to guess which one you mean:" >&2
  printf '  - %s\n' "${RUNNING[@]}" >&2
  echo "Stop one, or exec into the one you want directly: podman exec -it <name> bash" >&2
  exit 1
fi

CONTAINER_NAME="${RUNNING[0]}"
echo "Attaching to running container: ${CONTAINER_NAME}"
exec podman exec -it "${CONTAINER_NAME}" bash
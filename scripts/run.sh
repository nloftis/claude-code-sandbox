#!/usr/bin/env bash
# Ephemeral, one-shot session.
# Builds (if needed), drops you straight into `claude`, and deletes
# the container entirely on exit. Nothing persists except whatever
# lives in ../workspace on the host.
#
# Rootless Podman: no daemon, no root involved at any point in this
# chain - the container runs as your own unprivileged user.
#
# Auth: set CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token` on the
# host, recommended) or ANTHROPIC_API_KEY in .env. Either works.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_NAME="claude-code-sandbox"

podman build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  -t "${IMAGE_NAME}" \
  -f ./podman/Containerfile \
  ./podman

podman run --rm -it \
  --name claude-sandbox-ephemeral \
  --env-file .env \
  -v "$(pwd)/workspace:/home/claude/workspace" \
  "${IMAGE_NAME}" \
  claude --dangerously-skip-permissions
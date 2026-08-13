#!/usr/bin/env bash
# Ephemeral, one-shot session.
# Builds (if needed), drops you straight into `claude`, and deletes
# the container entirely on exit. Nothing persists except whatever
# lives in ../workspace on the host.
#
# Auth: set CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token` on the
# host, recommended) or ANTHROPIC_API_KEY in .env. Either works.
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE_NAME="claude-code-sandbox"

docker build \
  --build-arg UID="$(id -u)" \
  --build-arg GID="$(id -g)" \
  -t "${IMAGE_NAME}" \
  ./docker

docker run --rm -it \
  --name claude-sandbox-ephemeral \
  --env-file .env \
  -v "$(pwd)/workspace:/home/claude/workspace" \
  "${IMAGE_NAME}" \
  claude --dangerously-skip-permissions

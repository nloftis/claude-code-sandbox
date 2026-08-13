FROM node:22

# --- Build-time UID/GID -------------------------------------------
# Passing your host's UID/GID as build args means files created
# inside the container are owned by you on the host - no permission
# headaches on the mounted workspace, and ownership survives rebuilds.
ARG UID=1000
ARG GID=1000

# --- System deps -------------------------------------------------
# python3/pip/venv: many AI-assisted coding tasks are Python-based
# git/curl/ca-certificates: needed for Claude Code to clone/fetch things
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    git \
    curl \
    ca-certificates \
    less \
    vim \
    && rm -rf /var/lib/apt/lists/*

# --- Claude Code ---------------------------------------------------
RUN npm install -g @anthropic-ai/claude-code

# --- Non-root user ---------------------------------------------------
# node:22 ships a default `node` user - remove it first so the UID/GID
# we pass in isn't already taken, then create our `claude` user.
RUN userdel -r node 2>/dev/null || true \
    && groupadd -g ${GID} claude \
    && useradd -m -s /bin/bash -u ${UID} -g ${GID} claude

# Pre-seed onboarding so the container doesn't stop to ask first-run
# questions interactively.
RUN echo '{"hasCompletedOnboarding": true}' > /home/claude/.claude.json \
    && chown claude:claude /home/claude/.claude.json

USER claude
WORKDIR /home/claude/workspace

# Auth is supplied at runtime via --env-file, never baked in here.
# Either CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`, recommended)
# or ANTHROPIC_API_KEY works - see .env.example.

CMD ["claude"]
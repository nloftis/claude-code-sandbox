# claude-code-sandbox

A containerized, isolated environment for running [Claude Code](https://docs.claude.com/en/docs/claude-code) so it can operate autonomously (including with `--dangerously-skip-permissions`) without touching the host filesystem or credentials directly.

Container conventions here follow the approach described in *"The Age of AI: AI and Agentic Workflows"* by Keith Hubner, Linux Magazine, Issue 308 (July 2026).

## Why

Claude Code can execute shell commands, edit files, and install packages. Running it in a disposable Docker container instead of directly on the host limits the blast radius: worst case, the container gets torn down, not the host.

## What's in the container

- Node.js 22
- Python 3, with `pip` and `venv`
- Claude Code, installed globally
- A non-root `claude` user, built with your host UID/GID so files created in the mounted workspace stay owned by you (no permission headaches, ownership survives rebuilds)
- Onboarding pre-seeded so the container doesn't stop to ask first-run questions

## Structure

```
claude-code-sandbox/
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .dockerignore
├── scripts/
│   ├── run.sh       # ephemeral, one-shot: build + drop into `claude` + auto-delete on exit
│   ├── start.sh      # persistent: build (if needed) + start named container in background
│   ├── attach.sh      # exec a shell into the running persistent container
│   └── stop.sh         # stop + remove the persistent container
├── workspace/            # bind-mount target — project code goes here, not committed
├── .env.example            # copy to .env and fill in your auth
└── .gitignore
```

## Usage

### First-time auth

On the host, generate a token:

```bash
claude setup-token
```

Copy `.env.example` to `.env` and paste the token into `CLAUDE_CODE_OAUTH_TOKEN`. (An `ANTHROPIC_API_KEY` works as an alternative — set one or the other, not both.)

```bash
cp .env.example .env
```

### One-off session (recommended default)

```bash
./scripts/run.sh
```

Builds the image (passing your UID/GID as build args), drops you straight into `claude --dangerously-skip-permissions` inside the container, and deletes the container when you exit. Nothing persists except what's in `workspace/`.

### Persistent session

Use this if you want to step away and come back without losing in-container shell state.

```bash
./scripts/start.sh    # start (or resume) the named container in the background
./scripts/attach.sh   # get a shell inside it, then run: claude --dangerously-skip-permissions
./scripts/stop.sh      # tear it down when you're done
```

## Notes

- `workspace/` (mounted to `/home/claude/workspace` in the container) is the only thing bind-mounted in — Claude Code cannot see or touch anything else on the host. For project work that uses `CLAUDE.md` / `PLAN.md` / `LEARNINGS.md` / `.claude/` agent-and-skill conventions, that structure lives inside whatever project folder you mount as `workspace/`, not in this repo.
- `.env` holds your auth (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`) and is gitignored; never commit it. `.env.example` documents the variable names only.
- Both the one-off and persistent workflows build from the same `Dockerfile`, so the container itself is identical either way — the only difference is whether it's torn down on exit or kept running in the background. `docker-compose.yml` is just plumbing used by the persistent workflow, not a separate pattern.
- To fully cut network access for a given task, set `network_mode: none` in `docker/docker-compose.yml` or add `--network none` to the `docker run` flags in `scripts/run.sh`.
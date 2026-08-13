# claude-code-sandbox

A containerized, isolated environment for running [Claude Code](https://docs.claude.com/en/docs/claude-code) so it can operate autonomously (including with `--dangerously-skip-permissions`) without touching the host filesystem or credentials directly.

Container conventions here follow the approach described in *"The Age of AI: AI and Agentic Workflows"* by Keith Hubner, Linux Magazine, Issue 308 (July 2026), adapted from Docker to rootless Podman (see [Design consideration: Podman vs Docker](#design-consideration-podman-vs-docker) below).

## Why

Claude Code can execute shell commands, edit files, and install packages. Running it in a disposable, rootless container instead of directly on the host limits the blast radius: worst case, the container gets torn down, not the host.

## What's in the container

- Node.js 22
- Python 3, with `pip` and `venv`
- Claude Code, installed globally
- A non-root `claude` user, built with your host UID/GID so files created in the mounted workspace stay owned by you (no permission headaches, ownership survives rebuilds)
- Onboarding pre-seeded so the container doesn't stop to ask first-run questions

## Structure

```
claude-code-sandbox/
├── podman/
│   ├── Containerfile
│   └── .containerignore
├── scripts/
│   ├── run.sh       # ephemeral, one-shot: build + drop into `claude` + auto-delete on exit
│   ├── start.sh     # persistent: build (if needed) + start named container in background
│   ├── attach.sh    # exec a shell into the running persistent container
│   └── stop.sh      # stop + remove the persistent container
├── workspace/       # bind-mount target — project code goes here, not committed
├── .env.example     # copy to .env and fill in your auth
└── .gitignore
```

## Prerequisites

- **Podman**, installed on the host. On Pop!_OS / Ubuntu 22.04+:
  ```bash
  sudo apt update
  sudo apt install podman -y
  ```
  Verify rootless mode is active:
  ```bash
  podman info | grep rootless   # should show rootless: true
  ```
- **An Anthropic account** with Claude Code access (Pro/Max subscription, or API billing set up if using an API key instead).
- **Claude Code installed on the host, temporarily** — only needed to run `claude setup-token` once (see below). It is the *only* tool that can generate this token; there's no way to get it without the CLI installed somewhere. Once you have a token in `.env`, the host install can be removed — the container is fully self-sufficient after that point. If the token is ever revoked or expires, Claude Code has to go back on the host briefly to mint a new one.
  ```bash
  npm install -g @anthropic-ai/claude-code
  ```
  (Skip this entirely if using `ANTHROPIC_API_KEY` instead of a setup-token — an API key doesn't require the CLI to generate.)

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
./scripts/stop.sh     # tear it down when you're done
```

## Keeping Claude Code current

The image is not self-updating. `npm install -g @anthropic-ai/claude-code` in the `Containerfile` runs once, at build time — whatever version was current on npm at that moment gets frozen into that image layer permanently. Nothing inside a running or stopped container checks for a newer release.

A plain rebuild won't fix this either, because Podman caches build layers by instruction. If nothing above the `npm install` line in the `Containerfile` changed, the build reuses the cached layer (`Using cache`) instead of re-running it — so rebuilding repeatedly can silently keep serving the exact same Claude Code version indefinitely.

To force a genuine update:

```bash
# Re-runs every step fresh, including the npm install - guarantees current Claude Code
podman build --no-cache -t claude-code-sandbox -f ./podman/Containerfile ./podman

# Also re-checks for a newer node:22 base image, not just Claude Code
podman build --no-cache --pull -t claude-code-sandbox -f ./podman/Containerfile ./podman
```

Worth running this periodically — e.g., before a significant work session, or as a first troubleshooting step if something behaves unexpectedly, to rule out "stale cached version" before debugging further.

## Notes

- `workspace/` (mounted to `/home/claude/workspace` in the container) is the only thing bind-mounted in — Claude Code cannot see or touch anything else on the host. For project work that uses `CLAUDE.md` / `PLAN.md` / `LEARNINGS.md` / `.claude/` agent-and-skill conventions, that structure lives inside whatever project folder you mount as `workspace/`, not in this repo.
- `.env` holds your auth (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`) and is gitignored; never commit it. `.env.example` documents the variable names only.
- Both the one-off and persistent workflows build from the same `Containerfile`, so the container itself is identical either way — the only difference is whether it's torn down on exit or kept running in the background.
- To fully cut network access for a given task, add `--network none` to the `podman run` flags in `scripts/run.sh` (or `start.sh`).
- Keeping the host free of Claude Code entirely isn't fully achievable long-term: `claude setup-token` is a Claude Code subcommand, so the host needs a temporary install whenever the token needs to be generated or refreshed. Using `ANTHROPIC_API_KEY` instead avoids this, since API keys are generated from the Anthropic Console, not the CLI.
- `podman/.containerignore` is currently inert by design, not by accident: the build context is scoped to `podman/` (via `-f ./podman/Containerfile ./podman` in the scripts), so `.env`/`.git`/`workspace/` never enter the context in the first place, and the `Containerfile` has no `COPY`/`ADD` in normal operation that would pull context files into the image anyway. It was verified directly rather than left as an assumption: with a dummy `.env` placed in `podman/` and a temporary `COPY . /tmp/context-check` added to the `Containerfile`, the built image's `/tmp/context-check` contained only `Containerfile` and `.containerignore` — `.env` was correctly excluded. That confirms Podman 3.4 honors `.containerignore` correctly. If the build context or `Containerfile` ever changes to actually copy context files into the image, this exclusion is confirmed to hold; the same temporary-`COPY` method can be re-run to re-verify after any such change.

## How the isolation actually works

`workspace/` is the only shared space between the host and the container — think of it like a shared data partition between two operating systems on a dual-boot setup. Anything dropped into `workspace/` from the host is visible inside the container, and anything Claude Code creates or edits inside the container shows up on the host immediately, no export step. Everything *outside* that folder stays walled off in both directions.

This isn't enforced by a permission check that Claude Code could talk its way around. Containers get their own **mount namespace** — a kernel-level construct that gives every process inside the container its own private view of what filesystem exists. Even though the container shares the host's kernel (unlike a full VM, which has its own kernel), paths outside what's explicitly mounted in simply don't resolve to anything — there's no `/home/<user>` or host `/` visible from inside. A script Claude Code writes and runs inside the container isn't being blocked from reading the host filesystem; those paths never existed from where that process is standing.

Running under **rootless Podman** adds a second, stronger layer on top of that: there's no root-owned daemon anywhere in the chain orchestrating the container (see the design note below). The container also runs as a non-root `claude` user *inside* its own filesystem, on top of that.

**Caveats — things that would weaken this, none of which this scaffold does:**
- `--privileged` — disables most container security boundaries. Under rootless Podman this is already less severe than the Docker equivalent (it's still confined to your unprivileged user's namespace, not true host root), but it's still a bad idea and not used here.
- Exposing a container-engine API socket into the container — a classic escape vector, since it lets a container control the engine managing it. Docker's `dockerd` runs this by default; Podman's equivalent (`podman.sock`, via `podman system service`) is opt-in and not running here, so this risk doesn't currently apply at all — worth remembering only if `podman system service` is ever deliberately enabled later.
- Added capabilities (`--cap-add SYS_ADMIN`, etc.) — grants kernel-level powers beyond the default safe set, identically under both engines since they share the same OCI runtime. None added here.
- Kernel exploits — since the kernel *is* shared with the host, a container escape via a kernel vulnerability is theoretically possible regardless of engine or config. This isn't something the Containerfile controls; it's addressed by keeping the host kernel patched. Rootless mode limits the damage even here, since there's no root process for an escape to land in.

## Design consideration: Podman vs Docker

This project started with Docker, then switched to rootless Podman before either was actually installed on the host — worth documenting the reasoning since the two aren't quite interchangeable.

**The architectural difference:** Docker uses a client-server model — `dockerd` runs continuously as a root-owned background daemon, and the `docker` CLI just talks to it over a socket. Even a non-root user *inside* a Docker container is ultimately orchestrated by a root process on the host. Podman is daemonless: `podman run` directly forks and execs the container as a child of your own shell, using the same underlying OCI runtime Docker uses. Rootless is Podman's default mode — the entire container stack, not just the process inside it, runs under your own unprivileged UID.

**Why this matters for this specific project:** the whole point of this repo is containing an autonomous coding agent that can execute arbitrary commands. With Docker, a container-escape bug (rare, but the class of thing the caveats above are about) has root on the other side of it, because the daemon orchestrating everything is root. With rootless Podman, there's no root process anywhere in that chain — an escape lands as your own unprivileged user, not root. That's a meaningfully stronger match for the actual threat model here. It also fits the "ephemeral" philosophy more literally: no background daemon means nothing is running when nothing is being used.

**The tradeoffs, for completeness:**
- Most Claude Code / Docker tutorials (including the Linux Magazine article this repo is based on) assume Docker. Podman's CLI is close to a drop-in match for the commands used here, but troubleshooting help found online skews Docker.
- Rootless networking (`slirp4netns`/`pasta`) behaves differently from Docker's bridge networking in some cases — hasn't caused an issue for this repo's usage, but worth knowing if you extend it to publish ports or do more complex networking.
- Docker Compose has an official plugin; Podman's compose story on Ubuntu 22.04 (`podman` v3.4 from apt) doesn't bundle an equivalent, which is why this repo dropped `docker-compose.yml` in favor of the plain `start.sh`/`attach.sh`/`stop.sh` scripts instead of chasing a second tool (`podman-compose`) for a workflow three shell scripts already cover.

## Why local, not NAS-hosted

If you run containers elsewhere on your network (e.g., a Synology or other NAS), it's worth being deliberate about running this sandbox on the local workstation instead. Reasons:

- **Interactive latency.** Claude Code is a tight feedback loop — every command, every file edit streams back in near-real-time. Routing that through SSH to a NAS, even on LAN, adds latency that's felt over a long session. Local containers are effectively instant.
- **Access friction.** Execing into a local container is one command. A NAS-hosted container means SSH in first, then run the container command, then you're in — an extra hop and extra auth step for something done dozens of times per session.
- **Network segmentation adds real friction, not just inconvenience.** If your NAS sits on a separate VLAN/segment from your workstation, firewall rules between segments may restrict or complicate that SSH path — meaning this isn't just "more steps," it could mean opening firewall rules just to support a dev workflow.
- **Resource fit.** A NAS is usually tuned for its actual job (file serving, backups, monitoring stack, etc.). An AI coding agent running compile/test/lint loops is a bursty, CPU/memory-churny workload that competes with those services rather than complementing them.
- **GPU access, if relevant.** If you ever want to pair Claude Code with a local LLM setup, that only works on a machine with a GPU — most NAS units don't have one.

The one case where NAS-hosted containers *would* make sense: an always-on container reachable from multiple devices (e.g., kicking off a session from a laptop away from your desk). That's a different use case — a persistent remote dev environment — than what this repo is set up for.

## Conventions adopted from the Linux Magazine article

The following choices in this scaffold were carried over from *"The Age of AI: AI and Agentic Workflows"* by Keith Hubner (Linux Magazine, Issue 308, July 2026), translated from Docker to Podman where relevant:

- **Node.js 22 base image** and **Python 3 with `pip`/`venv`** installed alongside it, since AI-assisted coding tasks span both ecosystems.
- **Build-time `UID`/`GID` args** passed at build time, so files Claude Code creates in the mounted workspace are owned by you on the host rather than a generic container UID — no permission fixes needed after a session, and ownership survives image rebuilds.
- **A dedicated non-root `claude` user**, built at those UID/GID values (the base image's default `node` user is removed first so the UID isn't already taken).
- **Onboarding pre-seeded** via `{"hasCompletedOnboarding": true}` written into `/home/claude/.claude.json` at build time, so the container doesn't stop to ask first-run setup questions interactively.
- **Two supported auth paths**: `CLAUDE_CODE_OAUTH_TOKEN` (from running `claude setup-token` on the host, the article's recommended default) or `ANTHROPIC_API_KEY` as an alternative — both wired up via `.env`.
- **`claude --dangerously-skip-permissions`** as the default launch flag, which avoids being continuously prompted for per-action approval — made safe specifically *because* it's confined to the container rather than run on the host.
- **Workspace mounted at `/home/claude/workspace`**, matching the article's listings so paths line up if you're following it directly.

What this repo adds on top of the article (which only covers the ephemeral pattern, on Docker): the persistent-session workflow (`start.sh`/`attach.sh`/`stop.sh`), `.gitignore`/`.env.example` hygiene, and the switch to rootless Podman documented above.

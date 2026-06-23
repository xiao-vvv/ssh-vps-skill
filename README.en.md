<p align="center"><a href="README.md">简体中文</a> · <b>English</b></p>

<h1 align="center">ssh-vps-skill</h1>

<p align="center">An SSH-based VPS management skill for <b>AI agents</b> (Claude Code / openclaw / Codex, etc.)</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/shell-bash-121011?logo=gnu-bash&logoColor=white" alt="bash">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20openclaw%20%C2%B7%20Codex-8A2BE2" alt="works with Claude Code / openclaw / Codex">
</p>

> Just tell your AI "add this new box and disable password login" — it safely handles the SSH bootstrap for you.

This is not a web panel, nor a heavy ops platform you install on the server. It's a **skill**: one `SKILL.md` plus two self-contained bash scripts. Drop it into your AI agent and the agent learns how to manage all your boxes in a unified, secure way.

The underlying scripts also work by hand, but the real design goal is **"you speak plain language, the AI runs the scripts."**

---

## What it does

- 🔑 **One key for every box** — all machines use the same `~/.ssh/vps`; no more one-key-per-host mess
- 📇 **Alias management** — store IP / port / user as an alias in `~/.ssh/vps.config`, auto-`Include`d into `~/.ssh/config`, so even native `ssh <alias>` just works
- 📤 **One-shot public-key deploy** — enter the provider's password once; the public key is appended to the remote `authorized_keys`
- 🔒 **Safely disable password login** — **verifies key login works first and refuses to proceed if it doesn't**, so you never lock yourself out; also handles `sshd_config.d/` / cloud-init overrides and re-checks with `sshd -T`
- 🩺 **Bulk liveness + info** — see at a glance which box is online; query OS / kernel / CPU / memory / disk / uptime
- 🧩 **Fuzzy alias matching** — `tok` matches `tokyo-1`; ambiguous prefixes prompt you to be more specific

---

## Install

### One-liner (recommended)

```bash
bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

Installs to `~/.claude/skills/ssh-vps-skill` by default (Claude Code picks it up automatically). To choose another directory:

```bash
SSH_VPS_SKILL_DIR=~/your/skills/ssh-vps-skill bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

Re-running updates in place via `git pull`.

### Manual install (Claude Code)

Drop the whole directory into your skills folder:

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/.claude/skills/ssh-vps-skill
chmod +x ~/.claude/skills/ssh-vps-skill/scripts/*.sh
```

Claude Code will pick up the skill automatically. Just give instructions in natural language, e.g.:

> "Add the new box 1.2.3.4 as alias `myvps`, root password is `abcd1234`, then verify key login and disable password login."

The AI follows the conventions in `SKILL.md` to call the scripts.

### Other shell-capable AI agents (openclaw / Codex, etc.)

Any agent that can read files and run a shell can use it: put the repo somewhere the agent can reach, let it read `SKILL.md` to learn the command conventions, then have it call `scripts/ssh-vps.sh`.

### Manual use (no AI required)

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/ssh-vps-skill
chmod +x ~/ssh-vps-skill/scripts/*.sh
alias ssh-vps='~/ssh-vps-skill/scripts/ssh-vps.sh'   # add to ~/.zshrc / ~/.bashrc
```

---

## Requirements

Runs on **your local machine** (macOS / Linux). Needs: `bash`, `python3`, `openssh` (usually preinstalled), and `expect` (only for the "deploy key with password" step).

- macOS: `brew install expect`
- Debian / Ubuntu: `apt install -y expect`

**Do this once yourself first: generate the dedicated key** (the script will not generate it for you — it exits with an error if `~/.ssh/vps` is missing):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vps -C "vps-key"
```

You'll then have the private key `~/.ssh/vps` (**keep it local, never share it**) and the public key `~/.ssh/vps.pub` (safe to publish).

> **First-time note: the key, the SSH port, and the alias are all yours to set — nothing is forced:**
> - **Key / public key**: defaults to `~/.ssh/vps`. To use an existing key, put it at that path or point `VPS_KEY_PATH=/your/key` at it.
> - **SSH port**: the connect port defaults to `22` (fresh boxes are usually on 22; override with `--port`); the `port` command's default target is `20266` — use `ssh-vps port <alias> <your-port>` or set `VPS_HARDEN_PORT`.
> - **Alias**: the alias in `add <alias> <host>` is whatever you like (letters / digits / `.` / `_` / `-`), e.g. `tokyo-1`, `hk-bgp`.

---

## Command reference

```bash
ssh-vps init-key                                                    # first time: generate ~/.ssh/vps locally (skipped if it exists)
ssh-vps add <alias> <host> --user root --port 22 [--password 'pw']  # add/update alias; with a password it also deploys the key
ssh-vps sync-key <alias|host> --password 'pw'                        # deploy the public key only
ssh-vps <alias>                                                      # connect directly (fuzzy matching supported)
ssh-vps <alias> htop                                                 # run a remote command (interactive commands auto-allocate a PTY)
ssh-vps lock <alias>                                                 # verify key login, then disable password + keyboard-interactive (with sshd -t safety)
ssh-vps port <alias> [port]                                         # change SSH port (default 20266; keeps both + tests + auto-rollback)
ssh-vps list                                                         # list all aliases
ssh-vps status --all                                                 # bulk liveness check
ssh-vps info <alias>                                                 # show remote system info
ssh-vps rm <alias>                                                   # remove an alias
```

> **Port and key are configurable**: the port-change default target is `20266` — pass it explicitly with `ssh-vps port <alias> <port>` or change the default via `VPS_HARDEN_PORT`; the key path defaults to `~/.ssh/vps` and can point to your own key via `VPS_KEY_PATH`. See [Configuration](#configuration).

For multi-line remote scripts use `ssh-vps-run.sh` to avoid nested-quote hell:

```bash
ssh-vps-run.sh myvps <<'REMOTE'
set -euo pipefail
uname -a
ss -lnptu | head
REMOTE
```

---

## Configuration

| Setting | Default | How to change |
|---|---|---|
| Alias | none (you pick) | the name in `add <alias> <host>`; letters/digits/`.`/`_`/`-` |
| Key path | `~/.ssh/vps` | env `VPS_KEY_PATH` |
| Connect port | `22` | `VPS_DEFAULT_PORT`, or per-alias `--port` |
| Port-change target | `20266` | `VPS_HARDEN_PORT`, or `port <alias> <port>` |
| Default user | `root` | `VPS_DEFAULT_USER` |
| Password source | — | `--password` / `VPS_SSH_PASSWORD` / `--password-stdin` |

## Typical flow: from fresh box to locked down

```bash
# 0) First time: generate the dedicated key locally (skipped if present)
ssh-vps init-key

# 1) Add it + deploy the key (in one go)
ssh-vps add myvps 1.2.3.4 --user root --port 22 --password 'abcd1234'

# 2) Confirm key login works
ssh-vps myvps

# 3) Once key login works, disable password login (refuses to run if it can't get in first)
ssh-vps lock myvps

# 4) Optional: change the SSH port (default 20266; open the new port in your provider's firewall first)
ssh-vps port myvps
```

---

## Security notes

- The private key `~/.ssh/vps` must **never** be uploaded to a server, shared, or committed to any repo. This repo ships a `.gitignore` as a safety net, but verify it yourself.
- This repo contains **no** real IPs / passwords / keys — your actual connection details live locally in `~/.ssh/vps.config` and `~/.ssh/vps*`, unrelated to this repo.
- Before changing SSH config, `lock` verifies key login is usable — an intentional safety design. Still, always keep a working fallback login before any security change.

---

## License

MIT © xiaov

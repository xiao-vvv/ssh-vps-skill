<p align="center"><a href="README.md">简体中文</a> · <b>English</b></p>

<h1 align="center">ssh-vps-skill</h1>

<p align="center">An SSH-based VPS management skill for <b>AI agents</b> (Claude Code / openclaw / Codex, etc.)</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/shell-bash-121011?logo=gnu-bash&logoColor=white" alt="bash">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20openclaw%20%C2%B7%20Codex-8A2BE2" alt="works with Claude Code / openclaw / Codex">
</p>

> Just gently tell your AI "add this new box for me and turn off password login~" — it'll take care of the rest, safely.

It's not a heavy web panel, and you don't install it on the server. It's just a little **skill**: one `SKILL.md` plus two self-contained bash scripts. Drop it into your AI agent and it learns how to keep all your little boxes tidy and secure.

You can totally run the scripts by hand too, but what I really wanted was a gentle helper where **you talk and it does the work**~

---

## What it can do

- 🔑 **One key for all your boxes**: every machine uses the same `~/.ssh/vps`, so no more one-key-per-host headaches
- 📇 **A little alias notebook**: store IP / port / user as an alias in `~/.ssh/vps.config`, auto-wired into `~/.ssh/config`, so even native `ssh <alias>` just works
- 📤 **Send the public key up in one step**: type the provider's password once and the key is appended to the remote `authorized_keys`
- 🔒 **Disable password login, gently**: it **checks your key login actually works first, and won't touch anything if it can't get in**, so you'll never lock yourself out; it also tidies up those `sshd_config.d/` / cloud-init overrides and double-checks with `sshd -T` afterwards
- 🩺 **See all your boxes at a glance**: bulk liveness, plus OS / kernel / CPU / memory / disk / uptime
- 🧩 **Fuzzy alias matching**: type `tok` and it finds `tokyo-1`; if names clash it'll kindly ask you to be a bit more specific

---

## Install

### One-liner (recommended, easiest~)

```bash
bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

Installs to `~/.claude/skills/ssh-vps-skill` by default (Claude Code picks it up on its own). Want it somewhere else?

```bash
SSH_VPS_SKILL_DIR=~/your/skills/ssh-vps-skill bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

Run the same command again later and it updates in place via `git pull`~

### Manual install (Claude Code)

Just drop the whole directory into your skills folder:

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/.claude/skills/ssh-vps-skill
chmod +x ~/.claude/skills/ssh-vps-skill/scripts/*.sh
```

### Other shell-capable AI agents (openclaw / Codex, etc.)

As long as the agent can read files and run commands: put the repo somewhere it can reach, let it read `SKILL.md` for the command conventions, then have it call `scripts/ssh-vps.sh`~

### Prefer it fully by hand (no AI needed)

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/ssh-vps-skill
chmod +x ~/ssh-vps-skill/scripts/*.sh
alias ssh-vps='~/ssh-vps-skill/scripts/ssh-vps.sh'   # add to ~/.zshrc / ~/.bashrc
```

---

## A little prep before you start

It runs on **your own computer** (macOS / Linux). It needs `bash`, `python3`, `openssh` (usually already there), and `expect` (only for the "deploy key with password" step).

- macOS: `brew install expect`
- Debian / Ubuntu: `apt install -y expect`

**One thing to do yourself first: generate a dedicated key** (the script won't generate it for you — it'll gently remind you if `~/.ssh/vps` is missing):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vps -C "vps-key"
```

Now you'll have the private key `~/.ssh/vps` (**keep this one to yourself, never share it~**) and the public key `~/.ssh/vps.pub` (this one is fine to publish).

> **A first-time note: the key, the SSH port, and the alias are all yours to set however you like — nothing is mandatory:**
> - **Key / public key**: defaults to `~/.ssh/vps`. Already have a key? Put it at that path, or point `VPS_KEY_PATH=/your/key` at it.
> - **SSH port**: the connect port defaults to `22` (fresh boxes are usually on 22; override with `--port`); the `port` command's default target is `20266` — use `ssh-vps port <alias> <your-port>` or set `VPS_HARDEN_PORT`.
> - **Alias**: the alias in `add <alias> <host>` is totally up to you (letters / digits / `.` / `_` / `-`), e.g. `tokyo-1`, `hk-bgp`~

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

> **Port and key are yours to set~**: the port-change default target is `20266` — pass it explicitly with `ssh-vps port <alias> <port>` or change the default via `VPS_HARDEN_PORT`; the key path defaults to `~/.ssh/vps` and can point to your own key via `VPS_KEY_PATH`. See [Configuration](#configuration).

For multi-line remote scripts, use `ssh-vps-run.sh` so you don't have to wrestle with nested quotes~

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

---

## The whole flow: from fresh box to locked down

```bash
# 0) First time: generate the dedicated key locally (skip if you already have one)
ssh-vps init-key

# 1) Add it + send the key up (all in one)
ssh-vps add myvps 1.2.3.4 --user root --port 22 --password 'abcd1234'

# 2) Check that key login works
ssh-vps myvps

# 3) Once it works, safely disable password login (it won't act if it can't get in)
ssh-vps lock myvps

# 4) Want to change the port? (default 20266; open the new port in your provider's firewall first~)
ssh-vps port myvps
```

---

## A few security things I'd love you to keep in mind

- The private key `~/.ssh/vps` should **never** be uploaded to a server, shared, or committed to any repo. The repo ships a `.gitignore` as a safety net, but please double-check too~
- The repo contains **no** real IPs / passwords / keys — your actual connection details live locally in `~/.ssh/vps.config` and `~/.ssh/vps*`, nothing to do with this repo.
- Before changing SSH config, `lock` verifies your key login works — a little safety net I left on purpose. Still, always keep a working fallback login before any security change; better safe than sorry.

---

## License

MIT © xiaov

#!/usr/bin/env bash
set -uo pipefail

# /ssh_vps_manage
# By default use key: ~/.ssh/vps (never an external ssh-agent)

SCRIPT_NAME="$(basename "$0")"
SSH_MAIN_CONFIG="${SSH_MAIN_CONFIG:-$HOME/.ssh/config}"
SSH_CONFIG="${SSH_VPS_CONFIG:-$HOME/.ssh/vps.config}"
KEY_PATH="${VPS_KEY_PATH:-$HOME/.ssh/vps}"
PUB_KEY_PATH="${VPS_PUBLIC_KEY_PATH:-$HOME/.ssh/vps.pub}"
MANAGER_TAG="# SSH_VPS_MANAGE"
DEFAULT_USER="${VPS_DEFAULT_USER:-root}"
DEFAULT_PORT="${VPS_DEFAULT_PORT:-22}"

usage() {
  cat <<EOF
Usage:
  $SCRIPT_NAME add <alias> <host> [--user <user>] [--port <port>] [--password <password>]
  $SCRIPT_NAME rm <alias>
  $SCRIPT_NAME list
  $SCRIPT_NAME sync-key <alias|host> [--user <user>] [--port <port>] [--password <password>]
  $SCRIPT_NAME connect <alias|host[:port]|user@host[:port]> [remote-command...]
  $SCRIPT_NAME lock <alias>
  $SCRIPT_NAME status [alias|--all]
  $SCRIPT_NAME info <alias>
  $SCRIPT_NAME help

Notes:
  - Default key: ${KEY_PATH}
  - Default user: ${DEFAULT_USER}
  - Default port: ${DEFAULT_PORT}
  - Managed entries are written into ${SSH_CONFIG} (main file: ${SSH_MAIN_CONFIG})
  - Script auto-ensures: Include ~/.ssh/vps.config in ~/.ssh/config
  - Managed blocks always include IdentityAgent=/dev/null
EOF
}

ensure_keypair() {
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "Key not found: $KEY_PATH" >&2
    exit 1
  fi
  chmod 600 "$KEY_PATH" || true

  if [[ ! -f "$PUB_KEY_PATH" ]]; then
    ssh-keygen -y -f "$KEY_PATH" > "$PUB_KEY_PATH"
  fi
  chmod 644 "$PUB_KEY_PATH"
}

ensure_ssh_config_layout() {
  mkdir -p "$HOME/.ssh"
  [[ -f "$SSH_MAIN_CONFIG" ]] || touch "$SSH_MAIN_CONFIG"
  [[ -f "$SSH_CONFIG" ]] || touch "$SSH_CONFIG"
}

ensure_include_in_main() {
  python3 - "$SSH_MAIN_CONFIG" <<'PY'
import sys
from pathlib import Path

main = Path(sys.argv[1])
text = main.read_text() if main.exists() else ""
line = "Include ~/.ssh/vps.config"
if line in text:
    raise SystemExit(0)

lines = text.splitlines(keepends=True)
out = []
inserted = False
for ln in lines:
    out.append(ln)
    if (not inserted) and ln.strip().startswith("Include "):
        out.append(line + "\n")
        inserted = True

if not inserted:
    out.insert(0, line + "\n")

new_text = ''.join(out).rstrip('\n') + '\n'
main.write_text(new_text)
PY
}

# Python helper: 删除旧 block（marker 或普通 Host 块），并且按 alias 写入/更新
remove_alias_from_config() {
  local alias="$1"
  python3 - "$SSH_CONFIG" "$alias" <<'PY'
import re
import sys
from pathlib import Path

cfg, alias = sys.argv[1], sys.argv[2]
p = Path(cfg)
lines = p.read_text().splitlines(keepends=True)
out = []
i = 0
marker_begin = '# SSH_VPS_MANAGE BEGIN '
marker_end = '# SSH_VPS_MANAGE END '

while i < len(lines):
    line = lines[i]
    # remove managed marker block
    if line.strip() == marker_begin + alias:
        j = i + 1
        while j < len(lines) and lines[j].strip() != marker_end + alias:
            j += 1
        if j < len(lines):
            # Found matching END marker — skip the entire block
            i = j + 1
            continue
        # END marker missing — keep the line to avoid data loss
        out.append(line)
        i += 1
        continue

    # remove ordinary Host blocks containing alias
    m = re.match(r"^Host\s+(.+)$", line)
    if m:
        tokens = m.group(1).split()
        if alias in tokens:
            i += 1
            # remove until next Host/Match at column0
            while i < len(lines) and not re.match(r"^(Host|Match)\s+", lines[i]):
                i += 1
            continue
    out.append(line)
    i += 1

# keep one blank line between blocks for readability
text = ''.join(out).rstrip('\n') + '\n'
p.write_text(text)
PY
}

append_alias_to_config() {
  local alias="$1" host="$2" user="$3" port="$4"
  cat >> "$SSH_CONFIG" <<EOF

$MANAGER_TAG BEGIN ${alias}
Host ${alias}
  HostName ${host}
  User ${user}
  Port ${port}
  IdentityFile ~/.ssh/vps
  IdentitiesOnly yes
  IdentityAgent /dev/null
  UseKeychain yes
  AddKeysToAgent yes
  ServerAliveInterval 30
$MANAGER_TAG END ${alias}
EOF
}

add_alias() {
  local alias="$1" host="$2" user="$3" port="$4"
  ensure_include_in_main
  remove_alias_from_config "$alias"
  append_alias_to_config "$alias" "$host" "$user" "$port"
}

list_aliases() {
  python3 - "$SSH_CONFIG" <<'PY'
import re
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
in_block=False
cur={}
for line in lines:
    if line.startswith("# SSH_VPS_MANAGE BEGIN "):
        cur={"alias":line.split(" ",3)[3] if line.count(" ")>=3 else line.replace("# SSH_VPS_MANAGE BEGIN ","")}
        in_block=True
        continue
    if not in_block:
        continue
    if line.startswith("# SSH_VPS_MANAGE END "):
        print(f"{cur.get('alias',''):<18} {cur.get('host',''):<24} {cur.get('user',''):<10} {cur.get('port',''):<6}")
        in_block=False
        cur={}
        continue
    line=line.strip()
    parts=line.split(None,1)
    if len(parts)<2:
        continue
    if parts[0]=="HostName":
        cur['host']=parts[1]
    elif parts[0]=="User":
        cur['user']=parts[1]
    elif parts[0]=="Port":
        cur['port']=parts[1]
PY
}

resolve_alias_host() {
  local alias="$1"
  python3 - "$SSH_CONFIG" "$alias" <<'PY'
import re
import sys
from pathlib import Path
p = Path(sys.argv[1])
alias = sys.argv[2]
lines = p.read_text().splitlines()
in_block=False
host=port=user=""
for line in lines:
    if line.startswith("# SSH_VPS_MANAGE BEGIN "):
        if line.strip() == "# SSH_VPS_MANAGE BEGIN " + alias:
            in_block=True
        else:
            in_block=False
        continue
    if in_block:
        if line.startswith("# SSH_VPS_MANAGE END "):
            break
        s=line.strip()
        if s.startswith("HostName"):
            host=s.split(None,1)[1]
        elif s.startswith("User"):
            user=s.split(None,1)[1]
        elif s.startswith("Port"):
            port=s.split(None,1)[1]

print((host or "") + "|" + (port or "") + "|" + (user or ""))
PY
}

resolve_alias_fuzzy() {
  local needle="$1"
  python3 - "$SSH_CONFIG" "$needle" <<'PY'
import sys
from pathlib import Path

cfg = Path(sys.argv[1])
needle = sys.argv[2].strip().lower()
lines = cfg.read_text().splitlines()

aliases = []
for line in lines:
    if line.startswith("# SSH_VPS_MANAGE BEGIN "):
        aliases.append(line.replace("# SSH_VPS_MANAGE BEGIN ", "").strip())

if not aliases:
    print(needle)
    raise SystemExit(0)

# 1) case-insensitive exact
exact = [a for a in aliases if a.lower() == needle]
if len(exact) == 1:
    print(exact[0]); raise SystemExit(0)

# 2) case-insensitive prefix
prefix = [a for a in aliases if a.lower().startswith(needle)]
if len(prefix) == 1:
    print(prefix[0]); raise SystemExit(0)
if len(prefix) > 1:
    print("__AMBIGUOUS__:" + ",".join(prefix)); raise SystemExit(0)

# 3) case-insensitive contains
contains = [a for a in aliases if needle in a.lower()]
if len(contains) == 1:
    print(contains[0]); raise SystemExit(0)
if len(contains) > 1:
    print("__AMBIGUOUS__:" + ",".join(contains)); raise SystemExit(0)

# no alias match: keep original target
print(needle)
PY
}

sync_pubkey_to_host() {
  local host="$1" user="$2" port="$3" password="$4"
  ensure_keypair

  if [[ -z "$password" ]]; then
    echo "sync-key requires --password" >&2
    return 1
  fi

  local tmp_remote="/tmp/.vps_pub_$(date +%s)_$$"
  PASS="$password" \
  REMOTE_HOST="$host" \
  REMOTE_USER="$user" \
  REMOTE_PORT="$port" \
  REMOTE_TMP="$tmp_remote" \
  LOCAL_PUB="$PUB_KEY_PATH" \
  expect <<'EXPECT'
set timeout 45
set pass $env(PASS)
set host $env(REMOTE_HOST)
set user $env(REMOTE_USER)
set port $env(REMOTE_PORT)
set tmp $env(REMOTE_TMP)
set pub $env(LOCAL_PUB)

spawn /usr/bin/scp -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentityAgent=/dev/null -P $port "$pub" "$user@$host:$tmp"
expect {
  -re "(?i)password:" { send "$pass\r"; exp_continue }
  eof {}
  timeout { exit 2 }
}
lassign [wait] pid spawnid os_flag scp_exit
if {$scp_exit != 0} {
  puts stderr "ERROR: scp failed (exit $scp_exit)"
  exit 4
}

set remote_cmd "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys $tmp > ~/.ssh/authorized_keys.new && mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys && rm -f $tmp && echo synced"
spawn /usr/bin/ssh -tt -o StrictHostKeyChecking=accept-new -o PreferredAuthentications=password -o PubkeyAuthentication=no -o IdentityAgent=/dev/null -p $port "$user@$host" $remote_cmd
expect {
  -re "(?i)password:" { send "$pass\r"; exp_continue }
  -re "synced" { }
  eof {}
  timeout { exit 3 }
}
lassign [wait] pid spawnid os_flag ssh_exit
if {$ssh_exit != 0} {
  puts stderr "ERROR: ssh key-install failed (exit $ssh_exit)"
  exit 5
}
EXPECT
}

parse_target_port() {
  # outputs "host|port"
  local target="$1"

  if [[ "$target" == *"@"* ]]; then
    target="${target#*@}"
  fi

  if [[ "$target" == "["* && "$target" == *"]"* ]]; then
    # IPv6 literal without port support here
    echo "${target}|"
    return
  fi

  if [[ "$target" == *":"* && "$target" != *"["* ]]; then
    # host:port
    if [[ "$target" =~ ^([^:]+):([0-9]{1,5})$ ]]; then
      echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}"
      return
    fi
  fi

  echo "${target}|"
}

connect_target() {
  local input="$1"
  shift || true
  ensure_keypair

  local user="$DEFAULT_USER"
  local host_port="$input"
  local has_user=0

  if [[ "$input" == *"@"* ]]; then
    has_user=1
    user="${input%@*}"
    host_port="${input#*@}"
  fi

  local parsed parsed_host parsed_port
  parsed=$(parse_target_port "$host_port")
  parsed_host="${parsed%%|*}"
  parsed_port="${parsed##*|}"

  local opts=( -F "$SSH_CONFIG" -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o PubkeyAuthentication=yes -i "$KEY_PATH" -o StrictHostKeyChecking=accept-new )
  if [[ -n "$parsed_port" ]]; then
    opts+=( -p "$parsed_port" )
  fi

  local target="$input"
  # Strip :port from target when user provided user@host:port format
  if [[ "$has_user" -eq 1 && -n "$parsed_port" ]]; then
    target="${user}@${parsed_host}"
  fi
  if [[ "$has_user" -eq 0 ]]; then
    local alias_hit rec
    alias_hit=$(resolve_alias_fuzzy "$parsed_host")
    if [[ "$alias_hit" == __AMBIGUOUS__:* ]]; then
      echo "Ambiguous alias '$parsed_host': ${alias_hit#__AMBIGUOUS__:}" >&2
      echo "Tip: use a longer alias prefix." >&2
      return 2
    fi

    rec=$(resolve_alias_host "$alias_hit")
    if [[ -z "$rec" || "$rec" == "||" ]]; then
      target="${user}@${parsed_host}"
    else
      target="$alias_hit"
    fi
  fi

  # 当 stdin 是终端且传了远端命令时，自动加 -t 分配 PTY（支持 vim/htop/top/sudo 等交互式命令）
  if [[ -t 0 && $# -gt 0 ]]; then
    opts+=( -t )
  fi

  exec ssh "${opts[@]}" "$target" "$@"
}

add_cmd() {
  local alias="${1:-}"
  local host="${2:-}"
  [[ -z "$alias" ]] && { echo "Usage: $SCRIPT_NAME add <alias> <host> [options]" >&2; exit 2; }
  [[ "$alias" =~ [^a-zA-Z0-9._-] ]] && { echo "ERROR: alias 只允许字母、数字、点、下划线、连字符" >&2; exit 2; }
  [[ -z "$host" ]] && { echo "ERROR: missing host argument" >&2; exit 2; }
  [[ "$host" =~ [[:space:]] ]] && { echo "ERROR: host 不能包含空白字符" >&2; exit 2; }
  [[ "$host" =~ [^a-zA-Z0-9.:_-] ]] && { echo "ERROR: host 含有不安全字符 (仅允许字母、数字、.:_-)" >&2; exit 2; }
  local user="$DEFAULT_USER"
  local port="$DEFAULT_PORT"
  local password=""

  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) shift; user="${1:-$DEFAULT_USER}" ;;
      --port) shift; port="${1:-$DEFAULT_PORT}"; [[ "$port" =~ ^[0-9]+$ ]] || { echo "ERROR: port 必须为数字" >&2; exit 2; } ;;
      --password) shift; password="${1:-}" ;;
      *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
  done

  add_alias "$alias" "$host" "$user" "$port"
  if [[ -n "$password" ]]; then
    if ! sync_pubkey_to_host "$host" "$user" "$port" "$password"; then
      echo "WARNING: alias saved but key sync failed — run 'ssh-vps sync $alias' to retry" >&2
    fi
  fi
  echo "OK: added/updated alias '$alias' -> $user@$host:$port"
}

rm_cmd() {
  local alias="${1:-}"
  if [[ -z "$alias" ]]; then
    usage; exit 2
  fi
  remove_alias_from_config "$alias"
  echo "OK: removed '$alias'"
}

sync_cmd() {
  local target="${1:-}"
  local user="$DEFAULT_USER"
  local port="$DEFAULT_PORT"
  local password=""

  if [[ -z "$target" ]]; then
    usage; exit 2
  fi
  shift

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --user) shift; user="${1:-$DEFAULT_USER}" ;;
      --port) shift; port="${1:-$DEFAULT_PORT}" ;;
      --password) shift; password="${1:-}" ;;
      *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
  done

  # if target is managed alias (case-insensitive / fuzzy), read resolved host/port/user
  local alias_hit resolved
  alias_hit=$(resolve_alias_fuzzy "$target")
  if [[ "$alias_hit" == __AMBIGUOUS__:* ]]; then
    echo "Ambiguous alias '$target': ${alias_hit#__AMBIGUOUS__:}" >&2
    echo "Tip: use a longer alias prefix." >&2
    exit 2
  fi

  resolved=$(resolve_alias_host "$alias_hit")
  if [[ -n "$resolved" && "$resolved" != "||" ]]; then
    IFS='|' read -r host_r port_r user_r <<< "$resolved"
    target="$host_r"
    [[ -n "$port_r" ]] && port="$port_r"
    [[ -n "$user_r" ]] && user="$user_r"
  fi

  sync_pubkey_to_host "$target" "$user" "$port" "$password"
  echo "OK: public key synced to $user@$target:$port"
}

connect_cmd() {
  if [[ $# -lt 1 ]]; then
    usage; exit 2
  fi
  connect_target "$1" "${@:2}"
}

list_cmd() {
  echo "Alias              Host                     User       Port"
  echo "---------------------------------------------------------"
  list_aliases
}

get_all_aliases() {
  python3 - "$SSH_CONFIG" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
for line in p.read_text().splitlines():
    if line.startswith("# SSH_VPS_MANAGE BEGIN "):
        print(line.replace("# SSH_VPS_MANAGE BEGIN ", "").strip())
PY
}

lock_cmd() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "Usage: $SCRIPT_NAME lock <alias>" >&2
    exit 2
  fi

  local alias_hit resolved host port user
  alias_hit=$(resolve_alias_fuzzy "$target")
  if [[ "$alias_hit" == __AMBIGUOUS__:* ]]; then
    echo "Ambiguous alias '$target': ${alias_hit#__AMBIGUOUS__:}" >&2
    exit 2
  fi

  resolved=$(resolve_alias_host "$alias_hit")
  if [[ -z "$resolved" || "$resolved" == "||" ]]; then
    echo "Alias '$target' not found" >&2
    exit 1
  fi
  IFS='|' read -r host port user <<< "$resolved"

  echo "Verifying key login to $alias_hit ($user@$host:$port)..."
  if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=no -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -i "$KEY_PATH" -p "$port" "$user@$host" "echo ok" >/dev/null 2>&1; then
    echo "FAIL: key login failed. Cannot lock password before key works." >&2
    exit 1
  fi
  echo "OK: key login works."

  echo "Disabling password authentication on remote..."
  ssh -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -i "$KEY_PATH" -p "$port" "$user@$host" bash -s <<'REMOTE'
set -e

# Use sudo only when needed (skip if already root or sudo unavailable)
if [ "$(id -u)" -eq 0 ]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo "ERROR: not root and sudo not available" >&2
  exit 1
fi

# Use sshd -T to check the effective value (accounts for sshd_config.d/ overrides)
EFFECTIVE=$(sshd -T 2>/dev/null | grep -i '^passwordauthentication ' | awk '{print $2}')
if [ "$EFFECTIVE" = "no" ]; then
  echo "Already locked: PasswordAuthentication is already no (effective)"
  exit 0
fi

# Fix sshd_config.d/ overrides first (e.g. cloud-init)
if [ -d /etc/ssh/sshd_config.d ]; then
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] || continue
    if grep -qiE '^\s*PasswordAuthentication\s+yes' "$f"; then
      $SUDO sed -i -E 's/^\s*PasswordAuthentication\s+yes/PasswordAuthentication no/i' "$f"
      echo "Fixed override: $f"
    fi
  done
fi

# Fix main sshd_config
SSHD_CFG="/etc/ssh/sshd_config"
$SUDO sed -i.bak -E 's/^#?\s*PasswordAuthentication\s+.*/PasswordAuthentication no/' "$SSHD_CFG"
if ! grep -q '^PasswordAuthentication no' "$SSHD_CFG"; then
  echo 'PasswordAuthentication no' | $SUDO tee -a "$SSHD_CFG" >/dev/null
fi

if command -v systemctl >/dev/null 2>&1; then
  $SUDO systemctl restart sshd 2>/dev/null || $SUDO systemctl restart ssh 2>/dev/null
else
  $SUDO service sshd restart 2>/dev/null || $SUDO service ssh restart 2>/dev/null
fi

# Verify
AFTER=$(sshd -T 2>/dev/null | grep -i '^passwordauthentication ' | awk '{print $2}')
if [ "$AFTER" = "no" ]; then
  echo "Done: password authentication disabled (verified)"
else
  echo "WARNING: password authentication may still be enabled" >&2
  exit 1
fi
REMOTE
}

status_cmd() {
  local target="${1:-}"

  if [[ "$target" == "--all" || -z "$target" ]]; then
    local aliases
    aliases=$(get_all_aliases)
    if [[ -z "$aliases" ]]; then
      echo "No managed aliases found." >&2
      exit 0
    fi
    printf "%-18s %-24s %s\n" "Alias" "Host" "Status"
    echo "---------------------------------------------------------"
    while IFS= read -r a; do
      local rec
      rec=$(resolve_alias_host "$a")
      IFS='|' read -r h p u <<< "$rec"
      if ssh -n -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=no -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -i "$KEY_PATH" -p "${p:-22}" "$u@$h" "echo ok" >/dev/null 2>&1; then
        printf "%-18s %-24s \033[32monline\033[0m\n" "$a" "$h"
      else
        printf "%-18s %-24s \033[31moffline\033[0m\n" "$a" "$h"
      fi
    done <<< "$aliases"
  else
    local alias_hit resolved host port user
    alias_hit=$(resolve_alias_fuzzy "$target")
    if [[ "$alias_hit" == __AMBIGUOUS__:* ]]; then
      echo "Ambiguous alias '$target': ${alias_hit#__AMBIGUOUS__:}" >&2
      exit 2
    fi
    resolved=$(resolve_alias_host "$alias_hit")
    if [[ -z "$resolved" || "$resolved" == "||" ]]; then
      echo "Alias '$target' not found" >&2
      exit 1
    fi
    IFS='|' read -r host port user <<< "$resolved"
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o PasswordAuthentication=no -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -i "$KEY_PATH" -p "${port:-22}" "$user@$host" "echo ok" >/dev/null 2>&1; then
      echo "$alias_hit ($host): online"
    else
      echo "$alias_hit ($host): offline"
    fi
  fi
}

info_cmd() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    echo "Usage: $SCRIPT_NAME info <alias>" >&2
    exit 2
  fi

  local alias_hit resolved host port user
  alias_hit=$(resolve_alias_fuzzy "$target")
  if [[ "$alias_hit" == __AMBIGUOUS__:* ]]; then
    echo "Ambiguous alias '$target': ${alias_hit#__AMBIGUOUS__:}" >&2
    exit 2
  fi
  resolved=$(resolve_alias_host "$alias_hit")
  if [[ -z "$resolved" || "$resolved" == "||" ]]; then
    echo "Alias '$target' not found" >&2
    exit 1
  fi
  IFS='|' read -r host port user <<< "$resolved"

  echo "=== $alias_hit ($user@$host:$port) ==="
  ssh -o ConnectTimeout=10 -o IdentityAgent=/dev/null -o IdentitiesOnly=yes -i "$KEY_PATH" -p "$port" "$user@$host" bash -s <<'REMOTE'
echo "Hostname : $(hostname)"
echo "OS       : $(cat /etc/os-release 2>/dev/null | grep ^PRETTY_NAME | cut -d= -f2 | tr -d '"' || uname -s)"
echo "Kernel   : $(uname -r)"
echo "CPU      : $(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null) cores"
echo "Memory   : $(free -h 2>/dev/null | awk '/^Mem:/{print $2 " total, " $3 " used"}' || echo 'N/A')"
echo "Disk     : $(df -h / | awk 'NR==2{print $2 " total, " $3 " used, " $5 " usage"}')"
echo "IP       : $(hostname -I 2>/dev/null | awk '{print $1}' || ip addr show 2>/dev/null | grep 'inet ' | grep -v 127.0.0.1 | awk '{print $2}' | head -1)"
echo "Uptime   : $(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')"
REMOTE
}

main() {
  ensure_ssh_config_layout
  local cmd="${1:-help}"
  case "$cmd" in
    add)
      shift
      add_cmd "$@"
      ;;
    rm|remove|del)
      shift
      rm_cmd "$@"
      ;;
    sync-key)
      shift
      sync_cmd "$@"
      ;;
    list)
      list_cmd
      ;;
    lock)
      shift
      lock_cmd "$@"
      ;;
    status)
      shift
      status_cmd "$@"
      ;;
    info)
      shift
      info_cmd "$@"
      ;;
    connect)
      shift
      connect_cmd "$@"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      # 兼容：直接用 ip/alias 连接
      connect_cmd "$@"
      ;;
  esac
}

main "$@"

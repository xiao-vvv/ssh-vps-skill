#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VPS_SH="${VPS_SH:-$SCRIPT_DIR/ssh-vps.sh}"

usage() {
  cat <<'EOF'
Usage:
  ssh-vps-run.sh <alias|host[:port]|user@host[:port]> [--] [bash-args...]

Examples:
  bash skills/ssh_vps_manage/scripts/ssh-vps-run.sh myvps <<'REMOTE'
  set -euo pipefail
  uname -a
  ss -lnptu | head
  REMOTE

  bash skills/ssh_vps_manage/scripts/ssh-vps-run.sh myvps -- -eux <<'REMOTE'
  echo hello
  REMOTE

Notes:
  - Read the remote script from stdin and execute it as `bash -s` on the target.
  - Prefer this helper for multi-line remote work instead of stuffing long shell into nested quotes.
  - Reuse ssh-vps.sh alias/port/key resolution, including IdentityAgent=/dev/null.
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || $# -lt 1 ]]; then
  usage
  exit $([[ $# -lt 1 ]] && echo 2 || echo 0)
fi

TARGET="$1"
shift || true

if [[ ${1:-} == "--" ]]; then
  shift
fi

exec "$VPS_SH" connect "$TARGET" bash -s "$@"

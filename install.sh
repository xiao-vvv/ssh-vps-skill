#!/usr/bin/env bash
# ssh-vps-skill 一键安装
# 用法：
#   bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
# 自定义安装目录：
#   SSH_VPS_SKILL_DIR=~/my/skills/ssh-vps-skill bash <(curl -sL ...)
set -euo pipefail

REPO_URL="https://github.com/xiao-vvv/ssh-vps-skill.git"
TARBALL_URL="https://codeload.github.com/xiao-vvv/ssh-vps-skill/tar.gz/refs/heads/main"
DEST="${SSH_VPS_SKILL_DIR:-$HOME/.claude/skills/ssh-vps-skill}"

info() { printf '\033[32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }

info "安装目标目录：$DEST"

if command -v git >/dev/null 2>&1; then
  if [ -d "$DEST/.git" ]; then
    info "已存在，执行更新（git pull）..."
    git -C "$DEST" pull --ff-only
  else
    [ -e "$DEST" ] && { warn "目录已存在且非 git 仓库，先备份为 $DEST.bak"; mv "$DEST" "$DEST.bak.$(date +%s)"; }
    mkdir -p "$(dirname "$DEST")"
    info "git clone 中..."
    git clone --depth 1 "$REPO_URL" "$DEST"
  fi
else
  warn "未检测到 git，改用 curl + tar 下载..."
  [ -e "$DEST" ] && { warn "目录已存在，先备份"; mv "$DEST" "$DEST.bak.$(date +%s)"; }
  mkdir -p "$DEST"
  curl -fsSL "$TARBALL_URL" | tar -xz --strip-components=1 -C "$DEST"
fi

chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true

info "安装完成 → $DEST"
cat <<EOF

下一步：
  1) 首次使用先生成专用密钥（脚本不会替你生成）：
       ssh-keygen -t ed25519 -f ~/.ssh/vps -C "vps-key"

  2) 配 AI 用（推荐）：
       装在 ~/.claude/skills/ 下时，Claude Code 会自动识别这个 skill，
       直接对 AI 说「把这台新鸡加进来再关掉密码登录」即可。

  3) 纯手动用（可选）：
       alias ssh-vps='$DEST/scripts/ssh-vps.sh'
       ssh-vps add myvps 1.2.3.4 --user root --port 22 --password '密码'

详见 README：https://github.com/xiao-vvv/ssh-vps-skill
EOF

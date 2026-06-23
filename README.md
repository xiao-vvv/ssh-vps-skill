<p align="center"><b>简体中文</b> · <a href="README.en.md">English</a></p>

<h1 align="center">ssh-vps-skill</h1>

<p align="center">一个给 <b>AI agent</b>（Claude Code / openclaw 等）用的 VPS SSH 管理技能</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/shell-bash-121011?logo=gnu-bash&logoColor=white" alt="bash">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20openclaw-8A2BE2" alt="works with Claude Code / openclaw">
</p>

> 让你对 AI 说一句「把这台新鸡加进来，再关掉密码登录」，它就帮你安全地搞定 SSH 初始化。

这不是一个 Web 面板，也不是要装在服务器上的运维平台。它是一个 **skill**：一份 `SKILL.md` + 两个自包含的 bash 脚本，丢进你的 AI agent 里，AI 就学会了如何统一、安全地管理你手里所有的小鸡。

底层脚本也能纯手敲使用，但它真正的设计目标是 **「人说人话，AI 调脚本」**。

---

## 它能做什么

- 🔑 **统一一把密钥管所有小鸡** —— 所有机器都用同一把 `~/.ssh/vps`，告别每台一套
- 📇 **别名管理** —— IP / 端口 / 用户名存成别名，写进 `~/.ssh/vps.config` 并自动 `Include` 进 `~/.ssh/config`，连原生 `ssh <别名>` 都能直接用
- 📤 **一键下发公钥** —— 输一次服务商给的密码，自动把公钥追加进远端 `authorized_keys`
- 🔒 **安全地关密码登录** —— **先验证密钥能登，登不进就拒绝执行**，绝不会把你锁在门外；并自动处理 `sshd_config.d/` / cloud-init 这类云服务器常见的配置覆盖，最后用 `sshd -T` 复核生效
- 🩺 **批量探活 + 看配置** —— 一眼看哪台 online，查系统 / 内核 / CPU / 内存 / 磁盘 / 在线时长
- 🧩 **模糊别名匹配** —— `tok` 能命中 `tokyo-1`，多个候选会提示你写长一点

---

## 安装

### 一键安装（推荐）

```bash
bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

默认装到 `~/.claude/skills/ssh-vps-skill`（Claude Code 会自动识别）。想换目录：

```bash
SSH_VPS_SKILL_DIR=~/你的/skills/ssh-vps-skill bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

重复执行会自动 `git pull` 更新。

### 手动安装（Claude Code）

把整个目录放进你的 skills 目录即可：

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/.claude/skills/ssh-vps-skill
chmod +x ~/.claude/skills/ssh-vps-skill/scripts/*.sh
```

之后 Claude Code 会自动识别这个 skill。你直接用自然语言下指令即可，例如：

> 「把 1.2.3.4 这台新鸡用别名 myvps 加进来，root 密码是 abcd1234，然后验证密钥能登、再关掉密码登录。」

AI 会按 `SKILL.md` 里的约定去调用脚本完成。

### 其它能跑 shell 的 AI agent（openclaw 等）

任何能读文件 + 执行 shell 的 agent 都能用：把仓库放到 agent 可访问的目录，让它读 `SKILL.md` 了解命令约定，然后调用 `scripts/ssh-vps.sh`。

### 纯手动使用（不配 AI 也行）

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/ssh-vps-skill
chmod +x ~/ssh-vps-skill/scripts/*.sh
alias ssh-vps='~/ssh-vps-skill/scripts/ssh-vps.sh'   # 可写进 ~/.zshrc / ~/.bashrc
```

---

## 前置要求

跑在你**本地电脑**（macOS / Linux），需要：`bash`、`python3`、`openssh`（基本都自带），以及 `expect`（只有「用密码下发公钥」那步需要）。

- macOS：`brew install expect`
- Debian / Ubuntu：`apt install -y expect`

**第一步必须自己做一次：生成专用密钥**（脚本不会替你生成，没有 `~/.ssh/vps` 会直接报错退出）：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vps -C "vps-key"
```

生成后你会有私钥 `~/.ssh/vps`（**留在本地，绝不外传**）和公钥 `~/.ssh/vps.pub`（可公开）。

---

## 命令速查

```bash
ssh-vps add <别名> <host> --user root --port 22 [--password '密码']  # 加/更新别名；带密码则同时下发公钥
ssh-vps sync-key <别名|host> --password '密码'                       # 单独下发公钥
ssh-vps <别名>                                                       # 直接连接（支持模糊匹配）
ssh-vps <别名> htop                                                  # 跑远端命令（交互式自动分配 PTY）
ssh-vps lock <别名>                                                  # 验证密钥后关闭远端密码登录
ssh-vps list                                                         # 列出所有别名
ssh-vps status --all                                                 # 批量探活
ssh-vps info <别名>                                                  # 查远端系统信息
ssh-vps rm <别名>                                                    # 删除别名
```

多行远端脚本用 `ssh-vps-run.sh`，避免嵌套引号地狱：

```bash
ssh-vps-run.sh myvps <<'REMOTE'
set -euo pipefail
uname -a
ss -lnptu | head
REMOTE
```

---

## 典型流程：从拿到新鸡到锁好

```bash
# 1) 加进来 + 下发公钥（一步到位）
ssh-vps add myvps 1.2.3.4 --user root --port 22 --password 'abcd1234'

# 2) 确认密钥能登
ssh-vps myvps

# 3) 能登之后，再关密码登录（关之前进不去绝不执行）
ssh-vps lock myvps
```

---

## 安全说明

- 私钥 `~/.ssh/vps` **永远不上传服务器、不发给别人、不提交进任何仓库**。本仓库自带 `.gitignore` 兜底，但请自行确认。
- 本仓库代码**不含**任何真实 IP / 密码 / 密钥 —— 你的真实连接信息都在本地 `~/.ssh/vps.config` 与 `~/.ssh/vps*`，与本仓库无关。
- `lock` 改 SSH 配置前会先验证密钥登录可用，是有意为之的防呆设计；但任何安全变更前，仍建议你保留一个可用的备用登录方式。

---

## License

MIT © xiaov

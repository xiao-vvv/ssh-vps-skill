<p align="center"><b>简体中文</b> · <a href="README.en.md">English</a></p>

<h1 align="center">ssh-vps-skill</h1>

<p align="center">一个给 <b>AI agent</b>（Claude Code / openclaw / Codex 等）用的 VPS SSH 管理技能</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/shell-bash-121011?logo=gnu-bash&logoColor=white" alt="bash">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code%20%C2%B7%20openclaw%20%C2%B7%20Codex-8A2BE2" alt="works with Claude Code / openclaw / Codex">
</p>

> 你只要对 AI 轻轻说一句「帮我把这台新鸡加进来，再把密码登录关掉～」，剩下的它就替你稳稳搞定啦。

它不是那种很重的 Web 面板，也不用装在服务器上。它就是一个小小的 **skill**：一份 `SKILL.md` 加两个自带的 bash 脚本，丢进你的 AI agent 里，它就学会了怎么帮你把手上的小鸡们都安全、整齐地管起来。

底层脚本你想自己手敲也完全可以，不过我更希望它是那种 **「你动嘴、它动手」** 的小帮手～

---

## 它能做的事

- 🔑 **一把钥匙管所有小鸡**：所有机器都用同一把 `~/.ssh/vps`，再也不用每台一套、记到头大
- 📇 **别名小本本**：把 IP / 端口 / 用户名都记成别名，写进 `~/.ssh/vps.config` 并自动接进 `~/.ssh/config`，之后连系统原生的 `ssh <别名>` 都能用啦
- 📤 **公钥一键送上去**：服务商给的密码输一次，公钥就自动追加到远端的 `authorized_keys`，省心
- 🔒 **温柔地关掉密码登录**：会**先确认你的密钥真的能登进去，登不进就绝不动手**，所以不用怕把自己锁在门外；还会顺手处理 `sshd_config.d/` / cloud-init 那些云服务器爱搞的配置覆盖，最后用 `sshd -T` 再核对一遍才放心
- 🩺 **一眼看全家**：批量看哪台在线，查系统 / 内核 / CPU / 内存 / 磁盘 / 在线时长
- 🧩 **别名模糊匹配**：打 `tok` 就能找到 `tokyo-1`，要是撞名了它会提醒你写长一点点

---

## 怎么装

### 一键安装（推荐，最省事～）

```bash
bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

默认会装到 `~/.claude/skills/ssh-vps-skill`（Claude Code 自己就能认出来）。想换个地方也行：

```bash
SSH_VPS_SKILL_DIR=~/你的/skills/ssh-vps-skill bash <(curl -sL https://raw.githubusercontent.com/xiao-vvv/ssh-vps-skill/main/install.sh)
```

之后再跑同一条命令，它会自动 `git pull` 帮你更新～

### 手动安装（Claude Code）

把整个目录放进你的 skills 目录就好：

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/.claude/skills/ssh-vps-skill
chmod +x ~/.claude/skills/ssh-vps-skill/scripts/*.sh
```

### 其它能跑 shell 的 AI agent（openclaw / Codex 等）

只要这个 agent 能读文件、能执行命令就行：把仓库放到它够得着的地方，让它读一下 `SKILL.md` 了解命令约定，然后调用 `scripts/ssh-vps.sh` 就可以啦。

### 想纯手动用（不配 AI 也没问题）

```bash
git clone https://github.com/xiao-vvv/ssh-vps-skill.git ~/ssh-vps-skill
chmod +x ~/ssh-vps-skill/scripts/*.sh
alias ssh-vps='~/ssh-vps-skill/scripts/ssh-vps.sh'   # 可以写进 ~/.zshrc / ~/.bashrc
```

---

## 用之前的小准备

它跑在你**自己的电脑**上（macOS / Linux），需要 `bash`、`python3`、`openssh`（一般都自带），还有 `expect`（只有「用密码下发公钥」那一步才用得到）。

- macOS：`brew install expect`
- Debian / Ubuntu：`apt install -y expect`

**第一步要自己来一次：生成一把专属密钥**（脚本不会替你生成哦，没有 `~/.ssh/vps` 它会直接提醒你）：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vps -C "vps-key"
```

生成好之后你就有了私钥 `~/.ssh/vps`（**这把要自己收好，千万别外传～**）和公钥 `~/.ssh/vps.pub`（这把可以放心公开）。

> **初次使用的小提示：密钥、SSH 端口、别名都可以按你自己的喜好来设，没有非用不可的值哦：**
> - **密钥 / 公钥**：默认用 `~/.ssh/vps`。要是你已经有钥匙了，放到这个路径，或者设个环境变量 `VPS_KEY_PATH=/你的/密钥` 指过去就行。
> - **SSH 端口**：连接端口默认 `22`（新鸡一般就是 22，可以用 `--port` 改）；`port` 改端口的默认目标是 `20266`，你可以 `ssh-vps port <别名> <你想要的端口>`，或用 `VPS_HARDEN_PORT` 改默认。
> - **别名**：`add <别名> <host>` 里的别名你随便起（字母 / 数字 / `.` / `_` / `-` 都行），起个自己记得住的名字就好，比如 `tokyo-1`、`hk-bgp`～

---

## 命令速查

```bash
ssh-vps init-key                                                    # 首次：本地生成 ~/.ssh/vps（已存在则跳过）
ssh-vps add <别名> <host> --user root --port 22 [--password '密码']  # 加/更新别名；带密码则同时下发公钥
ssh-vps sync-key <别名|host> --password '密码'                       # 单独下发公钥
ssh-vps <别名>                                                       # 直接连接（支持模糊匹配）
ssh-vps <别名> htop                                                  # 跑远端命令（交互式自动分配 PTY）
ssh-vps lock <别名>                                                  # 验证密钥后关闭密码+键盘交互登录（含 sshd -t 防呆）
ssh-vps port <别名> [端口]                                           # 改 SSH 端口（默认 20266，新旧并存+实测+失败回滚）
ssh-vps list                                                         # 列出所有别名
ssh-vps status --all                                                 # 批量探活
ssh-vps info <别名>                                                  # 查远端系统信息
ssh-vps rm <别名>                                                    # 删除别名
```

> **端口和密钥都能自己定哦**：改端口默认目标是 `20266`，可以显式传 `ssh-vps port <别名> 端口`，或用环境变量 `VPS_HARDEN_PORT` 改默认值；密钥路径默认 `~/.ssh/vps`，也可以用 `VPS_KEY_PATH` 指向你自己的密钥。更多可调的见 [可配置项](#可配置项)。

多行的远端脚本就用 `ssh-vps-run.sh`，省得跟一堆嵌套引号较劲～

```bash
ssh-vps-run.sh myvps <<'REMOTE'
set -euo pipefail
uname -a
ss -lnptu | head
REMOTE
```

---

## 可配置项

| 配置 | 默认 | 怎么改 |
|---|---|---|
| 别名 | 无（自己起） | `add <别名> <host>` 里随便起，字母/数字/`.`/`_`/`-` |
| 密钥路径 | `~/.ssh/vps` | 环境变量 `VPS_KEY_PATH` |
| 连接端口 | `22` | `VPS_DEFAULT_PORT`，或每个别名的 `--port` |
| 改端口目标 | `20266` | `VPS_HARDEN_PORT`，或 `port <别名> <端口>` |
| 默认用户 | `root` | `VPS_DEFAULT_USER` |
| 密码来源 | — | `--password` / `VPS_SSH_PASSWORD` / `--password-stdin` |

---

## 一套走下来：从拿到新鸡到锁好

```bash
# 0) 首次：先在本地生成专属密钥（已经有了就跳过）
ssh-vps init-key

# 1) 加进来 + 顺便把公钥送上去（一步到位）
ssh-vps add myvps 1.2.3.4 --user root --port 22 --password 'abcd1234'

# 2) 确认一下密钥能登进去
ssh-vps myvps

# 3) 确认能登之后，再放心关掉密码登录（进不去它绝不动手哦）
ssh-vps lock myvps

# 4) 想改端口的话（默认 20266；记得先去服务商安全组放行新端口～）
ssh-vps port myvps
```

---

## 安全方面想跟你叮嘱的

- 私钥 `~/.ssh/vps` **千万别上传服务器、别发给别人、也别提交进任何仓库**。仓库自带了 `.gitignore` 帮你兜底，不过还是麻烦你自己也确认一下～
- 仓库里的代码**不含**任何真实 IP / 密码 / 密钥——你真正的连接信息都在本地的 `~/.ssh/vps.config` 和 `~/.ssh/vps*` 里，跟这个仓库没关系，放心。
- `lock` 在改 SSH 配置前会先确认密钥能登，这是特意留的一道保险；不过任何安全改动之前，都建议你先给自己留一条能用的备用登录方式，稳妥一点总是好的。

---

## License

MIT © xiaov

---
name: ssh_vps_manage
description: Manage VPS SSH aliases in ~/.ssh/vps.config (included from ~/.ssh/config) with unified key-based authentication and direct key sync.
---

# SSH VPS Manage

This skill focuses on **统一用 `~/.ssh/vps` 公钥连接**，并把连接信息写入 `~/.ssh/vps.config`（由 `~/.ssh/config` 通过 `Include ~/.ssh/vps.config` 引入）。
默认不走外部 ssh-agent（例如 1Password / Secretive 等 agent）。

## 目录
- `scripts/ssh-vps.sh`：增删查改别名、同步 key、直连。

## 使用方式（主命令）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh help
```

## 常用命令

### 列表
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh list
```

### 新增 / 更新别名（默认 key 连接）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh add <alias> <host> --user root --port 22
```

### 新增别名并写入公钥（提供密码时）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh add <alias> <host> --user root --port 22 --password '<password>'
```

### 删除别名
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh rm <alias>
```

### 同步公钥到远端（默认目标为 key + 端口）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh sync-key <alias> --password '<password>'
# 或直接传主机
bash skills/ssh_vps_manage/scripts/ssh-vps.sh sync-key <host> --user root --port 22 --password '<password>'
```

### 直接连接（默认支持别名和 IP）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh <alias>
bash skills/ssh_vps_manage/scripts/ssh-vps.sh <host>
bash skills/ssh_vps_manage/scripts/ssh-vps.sh <host>:<port>
bash skills/ssh_vps_manage/scripts/ssh-vps.sh <user>@<host>
bash skills/ssh_vps_manage/scripts/ssh-vps.sh connect <alias> "uname -a"
```

### 关闭密码登录（sync-key 后使用）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh lock <alias>
```
先验证密钥登录正常，再关闭远端 PasswordAuthentication，重启 sshd。

### 检测在线状态
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh status <alias>
bash skills/ssh_vps_manage/scripts/ssh-vps.sh status --all
```

### 查看远端系统信息
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh info <alias>
```
输出：系统版本、内核、CPU、内存、磁盘、IP、Uptime。

## 规则
- 新增/更新条目会写入 `~/.ssh/vps.config`（脚本会自动确保主配置包含 `Include ~/.ssh/vps.config`）：
  - `IdentityFile ~/.ssh/vps`
  - `IdentitiesOnly yes`
  - `IdentityAgent /dev/null`（默认不走外部 ssh-agent）
  - `UseKeychain yes`
  - `AddKeysToAgent yes`

## 注意
- 若你已在本会话里管理 VPS host，直接在别名方式添加即可，不再在技能内维护明文密码。
- 对于历史 host，不需要密码配置的可直接用 `add`+`--password` 重新同步 key 后切到 key 登录。
- 密钥优先本地 `~/.ssh/vps`。
- **交互式命令**：当 stdin 是终端且传了远端命令时，自动加 `-t` 分配 PTY。如 `ssh-vps.sh myvps htop`、`ssh-vps.sh myvps vim /etc/nginx/nginx.conf` 直接可用；无命令时（纯 shell 会话）SSH 默认开 PTY，无需手动加 `-t`。
- **经验约定**：凡是多行远端命令、里面再套引号/JSON/sed/awk/heredoc 的场景，默认不用 `ssh '...'` 这类单行嵌套写法；优先改用 `ssh-vps-run.sh <alias> <<'REMOTE' ... REMOTE`（示例见 `scripts/ssh-vps-run.sh`）。
- 在本地 `exec` 里需要先拼复杂脚本时，也优先先写临时脚本或单引号 heredoc，再调用 `ssh-vps-run.sh`，不要把多层引号直接塞进一条超长命令。
- **远程执行交互式安装脚本**（如 3X-UI、各类一键脚本）：不要把确认参数当位置参数传（`bash <(curl ...) y` 会被当版本号），也不要用 `echo "y" | bash <(curl ...)` 管道喂（管道关闭后后续交互提示读到空值，配置不生效）。正确做法：直接装默认值不传任何输入，装完用 CLI 命令单独配置（用户名、密码、端口等）。

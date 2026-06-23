---
name: ssh_vps_manage
description: Manage VPS SSH aliases in ~/.ssh/vps.config (included from ~/.ssh/config) with unified key-based authentication and direct key sync.
---

# SSH VPS Manage

This skill focuses on **统一用 `~/.ssh/vps` 公钥连接**，并把连接信息写入 `~/.ssh/vps.config`（由 `~/.ssh/config` 通过 `Include ~/.ssh/vps.config` 引入）。
默认不走外部 ssh-agent（例如 1Password / Secretive 等 agent）。

## 标准流程与安全契约（重要）
新机初始化的安全顺序，**务必按此执行**：
1. `init-key`（首次，本地生成 `~/.ssh/vps`，已存在则跳过）
2. `add <alias> <host> --password '<pw>'`（存别名 + 下发公钥）
3. `<alias>` 或 `status <alias>`：**验证密钥能登**
4. 确认能登后才 `lock <alias>`（关闭密码登录）；如需改端口再 `port <alias> [newport]`

- `lock` / `port` 是**破坏性、修改远端 sshd 的操作**，执行前必须先确认密钥可登；脚本本身也会先验证，验证不过会拒绝执行、不会把人锁在门外。
- 命令成功以 `OK:` / `Done:` 前缀输出，失败以 `FAIL:` / `ERROR:` 或非零退出码表示——据此判断结果。
- `port` 改端口前请提醒用户：**检查服务商安全组/外部防火墙是否放行新端口**，否则本机配好也连不上（脚本会实测新端口、连不上自动回滚到旧端口）。

## 目录
- `scripts/ssh-vps.sh`：增删查改别名、同步 key、直连。

## 使用方式（主命令）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh help
```

## 常用命令

### 生成本地密钥（首次）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh init-key
```
非交互生成 `~/.ssh/vps`（ed25519），已存在则不覆盖。

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

### 关闭密码登录（sync-key 并验证可登后使用）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh lock <alias>
```
先验证密钥登录正常；再关闭远端 `PasswordAuthentication` + `KbdInteractiveAuthentication` + `ChallengeResponseAuthentication`（处理 sshd_config.d / cloud-init 覆盖）；**重启前先 `sshd -t` 语法测试**（不过则还原备份、不重启），最后 `sshd -T` 复核生效。

### 修改 SSH 端口（默认 20266，可显式指定）
```bash
bash skills/ssh_vps_manage/scripts/ssh-vps.sh port <alias>          # 改到默认 20266
bash skills/ssh_vps_manage/scripts/ssh-vps.sh port <alias> 2222     # 显式端口
```
流程：验证旧端口可登 → 新旧端口并存 → 实测新端口 → 通过才切到仅新端口并更新别名；任何一步失败自动回滚旧端口。会尝试放行 ufw / firewalld（nftables 需手动放行）。

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
- **可配置项**（均有默认值，按需用环境变量/参数覆盖）：
  - 密钥路径：`VPS_KEY_PATH`（默认 `~/.ssh/vps`）
  - 默认连接端口：`VPS_DEFAULT_PORT`（默认 22）或每别名的 `--port`
  - `port` 目标端口：`VPS_HARDEN_PORT`（默认 20266）或 `port <alias> <newport>`
  - 默认用户：`VPS_DEFAULT_USER`（默认 root）
  - 密码来源：`--password` / 环境变量 `VPS_SSH_PASSWORD` / `--password-stdin`（避免明文进 ps / history）
- **交互式命令**：当 stdin 是终端且传了远端命令时，自动加 `-t` 分配 PTY。如 `ssh-vps.sh myvps htop`、`ssh-vps.sh myvps vim /etc/nginx/nginx.conf` 直接可用；无命令时（纯 shell 会话）SSH 默认开 PTY，无需手动加 `-t`。
- **经验约定**：凡是多行远端命令、里面再套引号/JSON/sed/awk/heredoc 的场景，默认不用 `ssh '...'` 这类单行嵌套写法；优先改用 `ssh-vps-run.sh <alias> <<'REMOTE' ... REMOTE`（示例见 `scripts/ssh-vps-run.sh`）。
- 在本地 `exec` 里需要先拼复杂脚本时，也优先先写临时脚本或单引号 heredoc，再调用 `ssh-vps-run.sh`，不要把多层引号直接塞进一条超长命令。
- **远程执行交互式安装脚本**（如 3X-UI、各类一键脚本）：不要把确认参数当位置参数传（`bash <(curl ...) y` 会被当版本号），也不要用 `echo "y" | bash <(curl ...)` 管道喂（管道关闭后后续交互提示读到空值，配置不生效）。正确做法：直接装默认值不传任何输入，装完用 CLI 命令单独配置（用户名、密码、端口等）。

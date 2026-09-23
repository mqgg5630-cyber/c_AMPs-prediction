# 新会话一句话提示词（v2.10.0）

复制到任何新的 Arena 对话即可：

```
安装https://github.com/mqgg5630-cyber/c_AMPs-prediction的 skills，与本机打通。
我的机器是linux，克隆目录放/home/w24e/0amp/att-lstm-bert，不要覆盖已有目录
```

（Windows 机器把最后一行换成 `我的机器是windows，克隆目录放 E:\0github\xxx`。）

## Agent 收到后的固定动作

1. `git clone --quiet --depth 1 -b arena/01a07992-c-amps-prediction https://github.com/mqgg5630-cyber/c_AMPs-prediction.git /tmp/git-sync-src && bash /tmp/git-sync-src/skills/git-sync/scripts/agent-install.sh`
2. `bash skills/git-sync/scripts/agent-sync.sh "feat: install git-sync"`
3. `bash skills/git-sync/scripts/agent-handoff.sh --linux <用户给的目录>`（Windows 不加 `--linux`），把输出块作为**第一条回复**给用户
4. `bash skills/git-sync/scripts/agent-check.sh --request "round 1: 本机打通自检"`
5. `bash skills/git-sync/scripts/agent-handsfree.sh --timeout auto` —— 本机值守自动 sync → 跑 `code/local_check.sh` → 推回 passed/failed；passed 即 `--accept` 闭环
6. 之后每次 Agent 完成工作：`agent-sync.sh "msg"` 推给本机（值守 `auto_pull` 自动拉），需要真机验证/执行就 `--request`（可先把命令写进 `code/job.sh`），结果自动 push 回来

## 用户侧只需一次的事

- WSL2：`bash proxy.sh --install`（宿主机 IP 漂移自动跟随；端口默认 10808 socks5，可 `PORT=7890 SCHEME=http`）
- 令牌：`bash auth.sh --add <仓库主账号>`（每台机器每个账号一次；`bootstrap.sh --auto` 之后自动按仓库主钉账号）
- cron：`sudo service cron start`；WSL 自启在 `/etc/wsl.conf` 加 `[boot]\ncommand=service cron start`

## 铁律

同一分支只准一侧值守 live（Windows / WSL / 第二台机三选一 `--register`，其他 `--unregister`）。

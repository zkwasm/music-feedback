# Logic-to-Sound Feedback for Claude Code

用声音反馈 Claude Code agent 的状态。每当 Claude 完成、报错、需要你介入、跑完一个长任务、或会话启停时，**在那一瞬间**用 macOS 系统音效播放一个可区分的"音乐动机"，让你不用盯屏也知道发生了什么。

需要你关注时（失败/需操作/告警/长任务）还能用 macOS `say` **语音念出是哪个 session 在叫**（见[语音播报](#语音播报是哪个-session)）。

基于 Claude Code 的 hook 机制（覆盖 9 类生命周期事件），纯 shell，**零第三方依赖、零配置**（不需要 API key）。

---

## 设计原则

- **即时**：分类只靠事件类型 / 关键词，**绝不调用 LLM/API**。延迟的声音是负资产——等你已在读输出时才"叮"一声，反而打断判断。
- **零配置零依赖**：macOS `afplay` + `/System/Library/Sounds`，无需安装任何东西，复用 Claude Code 已有登录。
- **绝不添乱**：脚本始终 `exit 0`、绝不阻断 Claude、**绝不修改系统音量**（只用 `afplay -v` 的单次增益）。

声音不是单个 beep，而是用 `afplay -r` 变调把一个采样拼成小**琶音/和弦**（上行、下行、门铃、三连 buzz……），更有辨识度、不单调。

---

## 声音映射（9 类，按优先级）

| 类别 | 触发 | 动机 | 优先级 |
|---|---|---|---|
| 🚨 **api-alarm** | `StopFailure`：API/系统错误（限流、认证失败、过载…，**与语言无关**） | Basso 低沉急促三连 buzz | 100 |
| ❌ **failure** | Stop 回复含 `error`/`failed`/`exception`/`denied` | Submarine 三音下行 | 80 |
| 🔔 **action** | 权限弹窗 / MCP 表单 / Stop 回复是提问（`?` 或 should I…） | Ping 门铃两音 ×2 | 70 |
| ⏱️ **long-tool** | 单个工具跑满 ≥ 30s 后完成 | Glass 高音三连 | 50 |
| ✅ **success** | Stop / SubagentStop 正常完成 | Glass 上行大三和弦 + 持续和弦 | 30 |
| 🗜️ **pre-compact** | 上下文压缩前 | Morse 节奏音 | 20 |
| ▶️ **session-start** | 会话启动 | Bottle 上行两音 | 15 |
| ⏹️ **session-end** | 会话结束（退出/logout/clear） | Bottle 下行两音 | 15 |
| 💤 **idle** | Claude 空闲等你输入（**默认关**，开启后限流） | Tink 单声柔音 | 10 |

分类优先级：失败/告警 > 需操作 > 其余。响度随优先级递增（重要音更响更亮）。

---

## 并发与抢占

不再用 `pgrep`（会被你放的音乐误吞）。改用状态目录 `~/.claude/feedback.state/` 协调：

- **只跟踪我们自己的播放**：放 Spotify / 别的音频时，我们的提示音**不会**被误吞。
- **按优先级抢占**：API 告警（100）能打断正在播的成功音（30）；成功音不会打断正在播的失败音。
- **跨会话互斥**：多个 Claude 窗口共享同一把锁（原子 `mkdir`）+ 同一个"扬声器占用"记录，不会乱成一团。
- **抗陈旧**：锁按 mtime 判旧，进程一律 `kill -0` + `ps` 命令名校验（避免 pid 复用误杀无关进程）。

---

## 环境要求

- **macOS**（`afplay` + `/System/Library/Sounds`）。`jq` 可选（缺失时降级 grep/sed）。
- 仅支持 macOS；Linux（`aplay`，无变调）未实现。

---

## 文件结构（Claude Code Plugin）

本仓库本身就是一个 **marketplace + plugin**：

```
music-feedback/
├── .claude-plugin/
│   └── marketplace.json          # marketplace 清单（指向下面的 plugin）
└── plugins/
    └── sound-feedback/
        ├── .claude-plugin/
        │   └── plugin.json       # plugin manifest
        ├── hooks/
        │   └── hooks.json        # 注册 9 类 hook（用 ${CLAUDE_PLUGIN_ROOT}）
        ├── scripts/
        │   └── feedback.sh       # 数据表 + 动机播放 + 并发抢占 + 路由（单脚本）
        └── commands/             # /sound-feedback:demo | :mute | :unmute
```
运行期（自动创建）：`~/.claude/feedback.state/`（锁 + 占用记录 + 工具计时）、可选 `~/.claude/feedback.{off,conf}`。

---

## 安装

### 作为 Plugin 安装（推荐）

在 Claude Code 里：
```
/plugin marketplace add /Users/tom/ai-workspace/music-feedback
/plugin install sound-feedback@music-feedback
```
> 推送到 GitHub 后，第一行可换成 `/plugin marketplace add <owner>/<repo>`，别人即可一键安装。

plugin 的 hook 与你已有的 `settings.json` hook **叠加共存**，不冲突。安装后 `/hooks` 可见，
改动后用 `/reload-plugins`（或重开会话）生效。自带命令：`/sound-feedback:demo`、`:mute`、`:unmute`。

### 本地试用（不安装）
```bash
claude --plugin-dir /Users/tom/ai-workspace/music-feedback/plugins/sound-feedback
```

### 校验
```bash
claude plugin validate ./plugins/sound-feedback   # plugin
claude plugin validate .                          # marketplace
```

---

## 配置

| 方式 | 作用 |
|---|---|
| `touch ~/.claude/feedback.off` | **全局静音**（`rm` 取消）。随时切换，无需重启会话 |
| `~/.claude/feedback.conf` | 可选覆盖文件，纯 shell 赋值（被 `source`，无需解析器） |
| 脚本顶部变量 | 调音色 / 音量 / 优先级 |

可覆盖的关键变量（写进 `feedback.conf` 或脚本顶部）：
```sh
MASTER_VOLUME=2.0       # 全局增益（afplay -v 倍数）
FEEDBACK_PROFILE=away   # away=成功也响；present=在场模式，成功静默，只在失败/需操作/告警时响
IDLE_ENABLED=0          # idle 默认关（它会反复触发）；设 1 开启
IDLE_MIN_GAP=300        # idle 最小间隔（秒），限流防吵
LONG_TOOL_SECS=30       # 工具耗时达到此值才提示
SND_success=Glass.aiff  # 各类音色：SND_<类>，可选见 ls /System/Library/Sounds/
VOL_action=1.0          # 各类音量：VOL_<类>
SPEAK_MODE=alerts       # 语音播报：off | alerts(默认,仅失败/需操作/告警/长任务) | all
SPEAK_MIN_PRIO=50       # alerts 模式阈值（≥此优先级才播报）
SPEAK_VOICE=            # say 的嗓音，如 Samantha；空=系统默认
SPEAK_RATE=             # say 语速(词/分)，空=默认
SPK_failure=failed      # 各类播报词(英文)：SPK_<类>，置空则该类不播报
```

### 语音播报「是哪个 session」
开了多个 Claude 窗口时，光听声音不知道是哪个在叫。`SPEAK_MODE`（默认 `alerts`）会在响完后用 macOS `say` 念出
**「session 标签 + 状态」**，例如 *"music feedback, failed"*、*"music feedback, needs you"*。
- **session 标签**：默认取工作目录名（`cwd` 的 basename）。`--name` 设的显示名 hook 拿不到，所以若想自定义，
  在启动 `claude` 前 `export CLAUDE_SESSION_LABEL="frontend"`，hook 会继承。
- 默认只在需要你关注的事件（失败/需操作/API告警/长任务完成）播报，避免每次成功都絮叨；`SPEAK_MODE=all` 则全部播报，`off` 关闭。
- 状态词为英文（延续"程序里无中文"）；标签是动态的，若目录名为中文，`say` 用英文嗓音读会含糊。

---

## 试听与测试

装好后在 Claude Code 里：`/sound-feedback:demo`。或直接调脚本：

```bash
SH=plugins/sound-feedback/scripts/feedback.sh

# 依次播放全部 9 个动机（带语音报名）
"$SH" --demo

# 干跑看分类（不出声）
echo '{"hook_event_name":"Stop","last_assistant_message":"build failed"}' \
  | CLAUDE_FEEDBACK_DEBUG=1 "$SH"
# -> event=Stop category=failure priority=80 speak=...
```

---

## 工作原理

1. hook 触发，Claude Code 把事件 JSON 经 **stdin** 喂给 `feedback.sh`。
2. 读 `hook_event_name` 路由；只有 Stop/SubagentStop 需读 `last_assistant_message` 做关键词分类。
3. 数据表查出该类的音色/音量/优先级 → `play_motif` 用多次 `afplay -r` 拼出动机。
4. 进并发闸：决定抢占 / 丢弃 / 播放，后台 `afplay`，hook 立即返回。
5. `PreToolUse` 记工具起始时间戳、`PostToolUse` 算耗时——只有 long-tool 这条用到工具级 hook（此路径极轻，不在每次工具调用时出声）。

---

## 已知局限与盲区

诚实清单：

- **按 ESC / Ctrl+C 中断** Claude → Stop 不触发 → 无声（目前没有 UserInterrupt hook，无法修复）。
- **非英文回复**：成功/失败靠英文关键词，中文"失败/请确认"匹配不到 → 正常结束的回合里会按成功响。**但真报错走 `StopFailure`，与语言无关照样告警**；提问靠 `?` 也能抓。
- **权限被自动批准/跳过**（acceptEdits / bypassPermissions / allowlist）→ 不弹框 → 不响"需操作"。
- **同优先级撞车**：忙时丢弃后来的同级/低级音（这是设计，避免叠音）。
- 系统**静音/音量 0**、**SSH/CI** 环境（已主动静音）下无声。
- `idle` 子类型依赖载荷里的 `idle_prompt` 标识；若实测字段不符，idle 会按"需操作"响（idle 默认关，影响小）。

### 不在 v1（按需再加）
Linux 支持、勿扰/专注/共享屏幕自动静音、GUI 配置、音色主题包、settings.json 自动合并安装器。

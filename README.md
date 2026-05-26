# Logic-to-Sound Feedback for Claude Code

Audio feedback for what your Claude Code agent is doing. The moment Claude finishes, errors out, needs you, completes a long task, or a session starts/ends, it plays a distinct **musical motif** through macOS system sounds — so you know what happened without watching the terminal.

When something needs your attention (failure / action / alarm / long task), it can also use macOS `say` to **speak which session is calling** (see [Spoken announcements](#spoken-which-session-announcements)).

Built on Claude Code's hook mechanism (covering 9 lifecycle events). Pure shell, **zero third-party dependencies, zero config** (no API key needed).

---

## Design principles

- **Instant**: classification uses only the event type / keywords — **never an LLM/API call**. A delayed sound is worse than none: a chime that lands while you're already reading the output just interrupts your judgment.
- **Zero config, zero deps**: macOS `afplay` + `/System/Library/Sounds`, nothing to install, reuses your existing Claude Code login.
- **Never gets in the way**: the script always `exit 0`, never blocks Claude, and **never changes your system volume** (only per-playback gain via `afplay -v`).

Sounds aren't single beeps — `afplay -r` pitch-shifts one sample into small **arpeggios/chords** (rising, falling, doorbell, triple buzz…), so they're recognizable and not monotonous.

---

## Sound map (9 categories, by priority)

| Category | Trigger | Motif | Priority |
|---|---|---|---|
| 🚨 **api-alarm** | `StopFailure`: API/system error (rate limit, auth failure, overload… **language-independent**) | Basso, low urgent triple buzz | 100 |
| ❌ **failure** | Stop reply contains `error`/`failed`/`exception`/`denied` | Submarine, three descending notes | 80 |
| 🔔 **action** | permission prompt / MCP dialog / Stop reply is a question (`?` or "should I…") | Ping, doorbell two-note ×2 | 70 |
| ⏱️ **long-tool** | a single tool ran ≥ 30s and finished | Glass, high triad | 50 |
| ✅ **success** | Stop / SubagentStop finished normally | Glass, rising major arpeggio + sustained chord | 30 |
| 🗜️ **pre-compact** | before context compaction | Morse, rhythmic tick | 20 |
| ▶️ **session-start** | session start | Bottle, rising two-note | 15 |
| ⏹️ **session-end** | session end (quit/logout/clear) | Bottle, descending two-note | 15 |
| 💤 **idle** | Claude idle, waiting for input (**off by default**, rate-limited when on) | Tink, single soft note | 10 |

Priority: failure/alarm > action > the rest. Loudness rises with priority (important sounds are louder/brighter).

---

## Concurrency & preemption

No more `pgrep` (which gets falsely suppressed by your music). Coordination goes through a state dir `~/.claude/feedback.state/`:

- **Tracks only our own playback**: playing Spotify / other audio does **not** suppress our cues.
- **Priority preemption**: an api-alarm (100) interrupts a playing success chime (30); a success will not interrupt a playing failure sound.
- **Cross-session mutual exclusion**: multiple Claude windows share one lock (atomic `mkdir`) and one "speaker owner" record, so they don't trample each other.
- **Stale-resistant**: the lock is judged stale by mtime; processes are always validated with `kill -0` + a `ps` command-name check (so a reused PID can never kill an unrelated process).

---

## Requirements

- **macOS** (`afplay` + `/System/Library/Sounds`). `jq` optional (falls back to grep/sed if absent).
- macOS only; Linux (`aplay`, no pitch-shift) is not implemented.

---

## Layout (Claude Code plugin)

This repo is itself a **marketplace + plugin**:

```
music-feedback/
├── .claude-plugin/
│   └── marketplace.json          # marketplace manifest (points to the plugin below)
└── plugins/
    └── sound-feedback/
        ├── .claude-plugin/
        │   └── plugin.json       # plugin manifest
        ├── hooks/
        │   └── hooks.json        # registers the 9 hooks (via ${CLAUDE_PLUGIN_ROOT})
        ├── scripts/
        │   └── feedback.sh       # data table + motif playback + concurrency + routing (single script)
        └── commands/             # /sound-feedback:demo | :mute | :unmute
```
Runtime (auto-created): `~/.claude/feedback.state/` (lock + owner record + tool timers), optional `~/.claude/feedback.{off,conf}`.

---

## Install

### As a plugin (recommended)

One-line install inside Claude Code:
```
/plugin marketplace add zkwasm/music-feedback
/plugin install sound-feedback@music-feedback
```
> Or from a local path: `/plugin marketplace add /path/to/music-feedback`.

The plugin's hooks **coexist additively** with any hooks you already have in `settings.json` — no conflict. After install they show up in `/hooks`; apply changes with `/reload-plugins` (or a new session). Bundled commands: `/sound-feedback:demo`, `:mute`, `:unmute`.

### Try locally (without installing)
```bash
claude --plugin-dir /path/to/music-feedback/plugins/sound-feedback
```

### Validate
```bash
claude plugin validate ./plugins/sound-feedback   # plugin
claude plugin validate .                          # marketplace
```

### Update
```
/plugin marketplace update music-feedback
/reload-plugins
```

### Uninstall
```
/plugin uninstall sound-feedback@music-feedback
```
Runtime files are left behind (safe to delete): `rm -rf ~/.claude/feedback.state ~/.claude/feedback.off ~/.claude/feedback.conf`

---

## Configuration

| Mechanism | Effect |
|---|---|
| `touch ~/.claude/feedback.off` | **Global mute** (`rm` to undo). Toggle anytime, no session restart |
| `~/.claude/feedback.conf` | Optional override file, plain shell assignments (`source`d, no parser) |
| Variables at the top of the script | Tune timbres / volumes / priorities |

Key overridable variables (put in `feedback.conf` or at the top of the script):
```sh
MASTER_VOLUME=2.0       # global gain (afplay -v multiplier)
FEEDBACK_PROFILE=away   # away=success chimes; present=at-desk mode, success silent, only failure/action/alarm sound
IDLE_ENABLED=0          # idle off by default (it re-fires); set 1 to enable
IDLE_MIN_GAP=300        # min seconds between idle nudges (rate limit)
LONG_TOOL_SECS=30       # only announce tools that ran at least this long
SND_success=Glass.aiff  # per-category timbre: SND_<cat>; options: ls /System/Library/Sounds/
VOL_action=1.0          # per-category volume: VOL_<cat>
SPEAK_MODE=alerts       # speech: off | alerts (default: failure/action/alarm/long-tool only) | all
SPEAK_MIN_PRIO=50       # alerts-mode threshold (speak only at priority >= this)
SPEAK_VOICE=            # say voice, e.g. Samantha; empty = system default
SPEAK_RATE=             # say rate (words/min); empty = default
SPK_failure=failed      # per-category spoken word (English): SPK_<cat>; empty = no speech for that category
```

### Spoken "which session" announcements
With several Claude windows open, a sound alone doesn't tell you which one is calling. `SPEAK_MODE` (default `alerts`) uses macOS `say` after the chime to speak **"session label + state"**, e.g. *"music feedback, failed"*, *"music feedback, needs you"*.
- **Session label**: defaults to the working-directory name (basename of `cwd`). The `--name` display name is *not* available to hooks, so to set a custom one, `export CLAUDE_SESSION_LABEL="frontend"` before launching `claude` and the hook inherits it.
- Speaks only for attention-worthy events by default (failure / action / API alarm / long-tool done), to avoid chattering on every success. `SPEAK_MODE=all` speaks everything; `off` disables it.
- State words are English (the program contains no hardcoded non-ASCII); the label is dynamic — a non-English folder name read by an English `say` voice will sound garbled.

---

## Demo & testing

After install, inside Claude Code: `/sound-feedback:demo`. Or call the script directly:

```bash
SH=plugins/sound-feedback/scripts/feedback.sh

# play all 9 motifs in sequence (with spoken labels)
"$SH" --demo

# dry-run to see classification (no sound)
echo '{"hook_event_name":"Stop","last_assistant_message":"build failed"}' \
  | CLAUDE_FEEDBACK_DEBUG=1 "$SH"
# -> event=Stop category=failure priority=80 speak=...
```

---

## How it works

1. A hook fires; Claude Code feeds the event JSON to `feedback.sh` over **stdin**.
2. The script routes on `hook_event_name`; only Stop/SubagentStop read `last_assistant_message` for keyword classification.
3. The data table yields the category's timbre/volume/priority → `play_motif` builds the motif with several `afplay -r` notes.
4. The concurrency gate decides preempt / drop / play, backgrounds `afplay`, and the hook returns immediately.
5. `PreToolUse` records a tool start timestamp; `PostToolUse` computes elapsed time — only the long-tool path uses tool-level hooks (this path is extremely light and stays silent on every ordinary tool call).

---

## Known limitations & blind spots

An honest list:

- **Pressing ESC / Ctrl+C** to interrupt Claude → Stop does not fire → no sound (there's no UserInterrupt hook yet; unfixable).
- **Non-English replies**: success/failure rely on English keywords, so a reply written in another language (e.g. "it failed" / "please confirm" in non-English) won't match → a normally-completed turn is heard as success. **But real errors come through `StopFailure`, which alarms regardless of language**; questions are also caught via `?`.
- **Permissions auto-approved/skipped** (acceptEdits / bypassPermissions / allowlist) → no prompt → no "action" sound.
- **Same-priority collision**: a busy speaker drops a newly arriving equal/lower-priority sound (by design, to avoid overlap).
- No sound when the system is **muted / volume 0**, or in **SSH/CI** environments (intentionally silenced).
- The `idle` subtype relies on an `idle_prompt` marker in the payload; if the real field differs, idle plays as "action" instead (idle is off by default, so low impact).
- **long-tool timing keys on `session_id`** (one timestamp per session). Tools running *in parallel* in the same session share that timestamp, so elapsed time can be mis-measured. Sequential tools — the common case (e.g. a long test run) — are accurate.

### Not in v1 (add on demand)
Linux support, DND/Focus/screen-share auto-mute, GUI config, sound-pack themes, an automatic `settings.json` merge installer.

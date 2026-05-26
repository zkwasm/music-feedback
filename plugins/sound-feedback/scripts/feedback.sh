#!/usr/bin/env bash
#
# feedback.sh - "Logic-to-Sound" feedback for Claude Code (macOS).
#
# Plays a distinct macOS system-sound motif the instant a Claude Code lifecycle
# event fires, so you know what the agent is doing without watching the terminal.
# Wire it to many hooks (see settings.json); it routes on `hook_event_name`.
#
# Design constraints (do not break):
#   * INSTANT: classification is keyword/event based -- never an LLM/API call.
#   * Zero-config, zero-dependency: macOS `afplay` + /System/Library/Sounds.
#   * Must ALWAYS exit 0, never block Claude, never change system volume
#     (only ever `afplay -v` per-playback gain).
#
# Motifs are built by playing one sample at several `afplay -r` rates (pitch),
# staggered with sleeps -> little arpeggios/chords. Concurrency is coordinated
# through ~/.claude/feedback.state so a high-priority alarm preempts a low one,
# our own playback is never suppressed by unrelated audio (e.g. Spotify), and
# multiple Claude sessions share one speaker safely.
#
# Usage / knobs:
#   feedback.sh --demo            audition every motif
#   CLAUDE_FEEDBACK_DEBUG=1       print resolved category, do not play
#   touch ~/.claude/feedback.off  global mute (rm to re-enable)
#   ~/.claude/feedback.conf       optional shell file sourced for overrides

HC="$HOME/.claude"
SOUND_DIR="/System/Library/Sounds"
STATE_DIR="$HC/feedback.state"
LOCK="$STATE_DIR/lock"
CUR="$STATE_DIR/current"
FALLBACK_SOUND="$SOUND_DIR/Tink.aiff"

# ---------- tunables (overridable via ~/.claude/feedback.conf) ----------
MASTER_VOLUME="${MASTER_VOLUME:-2.0}"     # global gain for afplay -v
FEEDBACK_PROFILE="${FEEDBACK_PROFILE:-away}"  # away=success sounds; present=silent on success
IDLE_ENABLED="${IDLE_ENABLED:-0}"         # idle_prompt off by default (it repeats)
IDLE_MIN_GAP="${IDLE_MIN_GAP:-300}"       # min seconds between idle nudges
LONG_TOOL_SECS="${LONG_TOOL_SECS:-30}"    # PostToolUse plays only if a tool ran >= this
[ -f "$HC/feedback.conf" ] && . "$HC/feedback.conf"

# Per-category sample / volume (x MASTER_VOLUME) / priority. conf may override.
: "${SND_api_alarm:=Basso.aiff}";      : "${VOL_api_alarm:=1.0}";      : "${PRIO_api_alarm:=100}"
: "${SND_failure:=Submarine.aiff}";    : "${VOL_failure:=1.0}";        : "${PRIO_failure:=80}"
: "${SND_action:=Ping.aiff}";          : "${VOL_action:=1.0}";         : "${PRIO_action:=70}"
: "${SND_long_tool:=Glass.aiff}";      : "${VOL_long_tool:=0.9}";      : "${PRIO_long_tool:=50}"
: "${SND_success:=Glass.aiff}";        : "${VOL_success:=1.0}";        : "${PRIO_success:=30}"
: "${SND_pre_compact:=Morse.aiff}";    : "${VOL_pre_compact:=0.8}";    : "${PRIO_pre_compact:=20}"
: "${SND_session_start:=Bottle.aiff}"; : "${VOL_session_start:=0.8}";  : "${PRIO_session_start:=15}"
: "${SND_session_end:=Bottle.aiff}";   : "${VOL_session_end:=0.7}";    : "${PRIO_session_end:=15}"
: "${SND_idle:=Tink.aiff}";            : "${VOL_idle:=0.6}";           : "${PRIO_idle:=10}"

# Spoken session announcement via macOS `say`. State words are English by design;
# the session label (cwd basename, or $CLAUDE_SESSION_LABEL) is read aloud after
# the chime so you know WHICH session is notifying.
SPEAK_MODE="${SPEAK_MODE:-alerts}"      # off | alerts (priority >= SPEAK_MIN_PRIO) | all
SPEAK_MIN_PRIO="${SPEAK_MIN_PRIO:-50}"  # alerts threshold: long-tool / action / failure / api-alarm
SPEAK_VOICE="${SPEAK_VOICE:-}"          # e.g. Samantha; empty = system default
SPEAK_RATE="${SPEAK_RATE:-}"            # words/min; empty = default
: "${SPK_api_alarm:=system error}"; : "${SPK_failure:=failed}";   : "${SPK_action:=needs you}"
: "${SPK_long_tool:=finished}";     : "${SPK_success:=done}";     : "${SPK_idle:=waiting}"
: "${SPK_pre_compact:=}";           : "${SPK_session_start:=}";   : "${SPK_session_end:=}"

# ---------- motif playback ----------
note() {  # sample volume rate stagger
  afplay -v "$2" -r "$3" "$1" >/dev/null 2>&1 &
  if [ "$4" != "0" ]; then sleep "$4"; fi
}

play_motif() {  # category (underscore form)
  local cat="$1" sv="SND_$1" vv="VOL_$1" snd vol
  snd="$SOUND_DIR/${!sv}"
  [ -f "$snd" ] || snd="$FALLBACK_SOUND"
  vol="$(awk -v a="${!vv}" -v b="$MASTER_VOLUME" 'BEGIN{printf "%.2f", a*b}')"
  case "$cat" in
    success)        # rising major arpeggio + sustained chord
      note "$snd" "$vol" 1.00 0.13; note "$snd" "$vol" 1.26 0.13
      note "$snd" "$vol" 1.50 0.13; note "$snd" "$vol" 2.00 0.34
      note "$snd" "$vol" 1.00 0;    note "$snd" "$vol" 1.50 0; note "$snd" "$vol" 2.00 0 ;;
    failure)        # three deep descending notes
      note "$snd" "$vol" 1.00 0.30; note "$snd" "$vol" 0.84 0.30; note "$snd" "$vol" 0.67 0 ;;
    action)         # doorbell ding-dong x2
      note "$snd" "$vol" 1.00 0.18; note "$snd" "$vol" 1.33 0.55
      note "$snd" "$vol" 1.00 0.18; note "$snd" "$vol" 1.33 0 ;;
    api_alarm)      # low insistent triple buzz
      note "$snd" "$vol" 0.95 0.16; note "$snd" "$vol" 0.95 0.16; note "$snd" "$vol" 0.72 0 ;;
    long_tool)      # bright high triad (distinct from success)
      note "$snd" "$vol" 1.50 0.12; note "$snd" "$vol" 1.89 0.12; note "$snd" "$vol" 2.25 0 ;;
    session_start)  # rising two-note "ready"
      note "$snd" "$vol" 1.20 0.14; note "$snd" "$vol" 1.60 0 ;;
    session_end)    # descending two-note "bye"
      note "$snd" "$vol" 1.50 0.16; note "$snd" "$vol" 1.00 0 ;;
    pre_compact)    # single rhythmic tick
      note "$snd" "$vol" 1.00 0 ;;
    idle)           # single soft nudge
      note "$snd" "$vol" 1.00 0 ;;
  esac
  wait
  # spoken "which session" announcement, after the chime (empty in --demo)
  if [ -n "${SPEAK_TEXT:-}" ]; then
    say ${SPEAK_VOICE:+-v "$SPEAK_VOICE"} ${SPEAK_RATE:+-r "$SPEAK_RATE"} "$SPEAK_TEXT" >/dev/null 2>&1
  fi
}

# ---------- concurrency / preemption ----------
ours_alive() {  # pid -> 0 if alive AND one of our processes (guards pid reuse)
  kill -0 "$1" 2>/dev/null || return 1
  case "$(ps -o command= -p "$1" 2>/dev/null)" in
    *feedback*|*afplay*) return 0 ;;
    *) return 1 ;;
  esac
}

play_gate() {  # priority category
  local prio="$1" cat="$2" got="" i now cprio cpid cstart lockm mp
  now="$(date +%s)"
  mkdir -p "$STATE_DIR" 2>/dev/null
  for i in 1 2 3 4 5; do
    if mkdir "$LOCK" 2>/dev/null; then got=1; break; fi
    if [ -d "$LOCK" ]; then
      lockm="$(stat -f %m "$LOCK" 2>/dev/null || echo 0)"
      [ $(( now - lockm )) -ge 3 ] && rmdir "$LOCK" 2>/dev/null
    fi
    sleep 0.01
  done
  [ -f "$CUR" ] && read -r cprio cpid cstart < "$CUR" 2>/dev/null
  if [ -n "${cpid:-}" ] && ours_alive "$cpid"; then
    if [ "$prio" -gt "${cprio:-0}" ]; then
      pkill -P "$cpid" 2>/dev/null; kill "$cpid" 2>/dev/null   # preempt lower priority
    else
      [ -n "$got" ] && rmdir "$LOCK" 2>/dev/null
      return 0                                                 # equal/higher owns speaker: drop
    fi
  fi
  ( play_motif "$cat" ) &
  mp=$!
  disown 2>/dev/null || true
  printf '%s %s %s\n' "$prio" "$mp" "$now" > "$CUR" 2>/dev/null
  [ -n "$got" ] && rmdir "$LOCK" 2>/dev/null
  return 0
}

# ---------- helpers ----------
get_event() {
  local e
  e="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
  [ -z "$e" ] && e="$(printf '%s' "$INPUT" | grep -o '"hook_event_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  printf '%s' "$e"
}

json_str() {  # key -> value (jq, grep fallback)
  local v
  v="$(printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null)"
  [ -z "$v" ] && v="$(printf '%s' "$INPUT" | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
  printf '%s' "$v"
}

session_label() {  # which session to speak: $CLAUDE_SESSION_LABEL, else cwd basename
  [ -n "${CLAUDE_SESSION_LABEL:-}" ] && { printf '%s' "$CLAUDE_SESSION_LABEL"; return; }
  local c; c="$(json_str cwd)"
  if [ -n "$c" ]; then basename "$c" | tr '_-' '  '; else printf 'session'; fi
}

classify_stop() {  # echo failure|action|success|"" from the final reply text
  local msg hay last
  msg="$(json_str last_assistant_message)"
  [ -z "$msg" ] && msg="$INPUT"
  hay="$(printf '%s' "$msg" | tr '[:upper:]' '[:lower:]')"
  case "$hay" in
    *error*|*failed*|*failure*|*exception*|*denied*) printf 'failure'; return ;;
  esac
  case "$hay" in
    *permission*|*confirm*|*approve*|*"your input"*|*"let me know"*|*"should i"*|*"do you want"*|*"which "*)
      printf 'action'; return ;;
  esac
  last="$(printf '%s' "$msg" | tr -d '[:space:]' | tail -c 1)"   # ASCII '?' only (no Chinese in program)
  [ "$last" = "?" ] && { printf 'action'; return; }
  [ "$FEEDBACK_PROFILE" = "present" ] && { printf ''; return; }
  printf 'success'
}

idle_gate() {  # 0 if enough time since last idle nudge (and records now)
  local f now last
  f="$STATE_DIR/idle.last"; now="$(date +%s)"
  mkdir -p "$STATE_DIR" 2>/dev/null
  [ -f "$f" ] && last="$(cat "$f" 2>/dev/null)"
  [ $(( now - ${last:-0} )) -ge "$IDLE_MIN_GAP" ] || return 1
  echo "$now" > "$f" 2>/dev/null
  return 0
}

classify_notification() {
  case "$INPUT" in
    *idle_prompt*)
      [ "$IDLE_ENABLED" = "1" ] || { printf ''; return; }
      idle_gate || { printf ''; return; }
      printf 'idle' ;;
    *) printf 'action' ;;   # permission_prompt / elicitation / anything needing you
  esac
}

tool_key() {
  local k
  k="$(json_str session_id)"; [ -z "$k" ] && k=default
  printf '%s' "$k" | tr -c 'A-Za-z0-9_.-' '_'
}

tool_start() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  date +%s > "$STATE_DIR/tool.$(tool_key)" 2>/dev/null
}

tool_end() {  # sets CATEGORY=long-tool, or exits 0
  local f start now
  f="$STATE_DIR/tool.$(tool_key)"
  [ -f "$f" ] || exit 0
  start="$(cat "$f" 2>/dev/null)"; rm -f "$f" 2>/dev/null
  now="$(date +%s)"
  [ $(( now - ${start:-now} )) -ge "$LONG_TOOL_SECS" ] || exit 0
  CATEGORY="long-tool"
}

sweep_state() {  # tidy stale files on session start
  mkdir -p "$STATE_DIR" 2>/dev/null
  find "$STATE_DIR" -name 'tool.*' -mmin +60 -delete 2>/dev/null
  [ -d "$LOCK" ] && rmdir "$LOCK" 2>/dev/null
}

run_demo() {
  local c
  for c in session_start success long_tool action failure api_alarm pre_compact idle session_end; do
    echo ">>> $c"
    say "${c//_/ }" 2>/dev/null
    play_motif "$c"
    sleep 0.6
  done
}

# ---------- main ----------
[ "${1:-}" = "--demo" ] && { run_demo; exit 0; }

INPUT="$(cat)"

[ -f "$HC/feedback.off" ] && exit 0                       # global mute
[ -n "${CI:-}${SSH_CONNECTION:-}${SSH_TTY:-}" ] && exit 0 # CI / SSH: no local speaker

event="$(get_event)"
CATEGORY=""
case "$event" in
  StopFailure)       CATEGORY="api-alarm" ;;
  Stop|SubagentStop) CATEGORY="$(classify_stop)" ;;
  SessionStart)      sweep_state; CATEGORY="session-start" ;;
  SessionEnd)        CATEGORY="session-end" ;;
  PreCompact)        CATEGORY="pre-compact" ;;
  PreToolUse)        tool_start; exit 0 ;;
  PostToolUse)       tool_end ;;
  Notification)      CATEGORY="$(classify_notification)" ;;
  *)                 exit 0 ;;
esac

[ -z "$CATEGORY" ] && exit 0

cat_var="$(printf '%s' "$CATEGORY" | tr '-' '_')"
pv="PRIO_$cat_var"; prio="${!pv:-0}"

# decide spoken announcement
SPEAK_TEXT=""
if [ "$SPEAK_MODE" != "off" ]; then
  spk_var="SPK_$cat_var"; phrase="${!spk_var:-}"
  if [ -n "$phrase" ] && { [ "$SPEAK_MODE" = "all" ] || [ "$prio" -ge "$SPEAK_MIN_PRIO" ]; }; then
    SPEAK_TEXT="$(session_label), $phrase"
  fi
fi

if [ "${CLAUDE_FEEDBACK_DEBUG:-}" = "1" ]; then
  echo "event=${event:-?} category=$CATEGORY priority=$prio speak=${SPEAK_TEXT:-(none)}"
  exit 0
fi

play_gate "$prio" "$cat_var"
exit 0

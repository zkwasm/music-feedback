---
description: Mute Claude sound feedback (creates ~/.claude/feedback.off)
allowed-tools: Bash(touch:*)
---
!`touch "$HOME/.claude/feedback.off" && echo "🔇 sound-feedback muted — run /sound-feedback:unmute to re-enable"`

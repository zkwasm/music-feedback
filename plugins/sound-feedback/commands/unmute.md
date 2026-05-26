---
description: Unmute Claude sound feedback (removes ~/.claude/feedback.off)
allowed-tools: Bash(rm:*)
---
!`rm -f "$HOME/.claude/feedback.off" && echo "🔔 sound-feedback unmuted"`

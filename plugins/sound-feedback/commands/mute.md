---
description: Mute Claude sound feedback
allowed-tools: Bash(touch:*)
---
Mute the sound-feedback plugin by creating its sentinel file, then confirm to the user:

```bash
touch "$HOME/.claude/feedback.off" && echo "sound-feedback muted (run /sound-feedback:unmute to re-enable)"
```

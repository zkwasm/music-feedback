---
description: Unmute Claude sound feedback
allowed-tools: Bash(rm:*)
---
Unmute the sound-feedback plugin by removing its sentinel file, then confirm to the user:

```bash
rm -f "$HOME/.claude/feedback.off" && echo "sound-feedback unmuted"
```

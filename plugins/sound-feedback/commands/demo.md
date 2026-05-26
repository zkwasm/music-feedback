---
description: Play a demo of all sound-feedback motifs (~30s)
allowed-tools: Bash(*)
---
Run the bundled demo script to audition every motif. It plays ~9 sounds over ~30s, so run it in the background (don't wait for it):

```bash
nohup "${CLAUDE_PLUGIN_ROOT}/scripts/feedback.sh" --demo >/dev/null 2>&1 &
```

Then tell the user the demo is playing.

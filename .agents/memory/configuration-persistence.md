---
name: Saved configuration behavior
description: Persist user preferences without automatically restarting active farm or travel sessions.
---

Load saved preference values when the hub starts, but do not restore active Main Farm or travel runtime state.

**Why:** The user approved auto-saving settings while keeping active farm/travel sessions from unexpectedly resuming after script reload.

**How to apply:** Keep saved settings separate from runtime activation. A remembered hop preference may be on, but it must not initiate a server change merely because the hub loaded.

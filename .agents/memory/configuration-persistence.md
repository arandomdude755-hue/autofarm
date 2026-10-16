---
name: Saved configuration behavior
description: Persist user preferences without automatically restarting active farm or travel sessions.
---

Load saved preference values when the hub starts, but do not restore active Main Farm or travel runtime state.

**Why:** The user approved auto-saving settings while keeping active farm/travel sessions from unexpectedly resuming after script reload.

**How to apply:** Keep saved settings separate from runtime activation. A remembered hop preference may be on, but it must not initiate a server change merely because the hub loaded.

Share UI appearance preferences across Roblox accounts using the same executor storage, but keep team, farming, travel, and other operational settings account-specific.

**Why:** the user asked for UI settings to be universal across accounts, while explicitly limiting that sharing to UI preferences.

**How to apply:** Store interface preferences separately from per-account gameplay settings; do not move Auto Execute or automation toggles into shared settings.

On Delta, the `queue_on_teleport` marker successfully ran after a teleport even when the full hub reload did not.

**Why:** the user's test confirmed the queue API works there, so a missing hub window points to the loader after the queued script starts rather than queue registration.

**How to apply:** Keep queue execution, bundle download/compilation, and hub startup as separately reported stages when debugging Auto Execute.

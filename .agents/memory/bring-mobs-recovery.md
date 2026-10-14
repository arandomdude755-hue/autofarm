---
name: Bring Mobs recovery
description: Safety rules for moving live NPCs during Bring Mobs and recovering stalled targets.
---

When Bring Mobs relocates a live NPC, keep a short health-progress watchdog. If it remains alive, close to the farm target, and undamaged, restore its original root transform and avoid bringing that same instance again during the session. Do not add a persistent `Ignored` child; that marker can affect normal farm target selection.

**Why:** The BNN reference checks network ownership and restores NPCs that do not take damage after a short interval. CustomHub has no equivalent ownership helper, so rollback is the available safeguard against leaving a client-moved NPC in a desynchronized or unresponsive state.

**How to apply:** Preserve the existing Bring Mobs name matching, player-distance checks, group cap, and per-tick movement bound. Treat the rollback as a mitigation, not proof that an NPC is client-owned or that all in-game desyncs are prevented; verify this behavior in Roblox.

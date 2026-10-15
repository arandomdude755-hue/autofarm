---
name: Movement stall evidence
description: How to interpret no-obstacle movement stalls in the shared Roblox movement engine.
---

A clear forward raycast only says that no geometry was hit along that short corridor. It does not show that the client root accepted its commanded CFrame, that another script did not overwrite it, or that replication/physics is advancing the character. Compare the root's distance from its last commanded position with remaining goal distance before classifying a stall.

**Why:** movement can stop progressing even when the obstacle diagnostic is clear because the progress watchdog measures actual root displacement, while the raycast measures only nearby geometry.

**How to apply:** on a stall, preserve the owning travel request while retrying the same leg within a bounded window; avoid treating a no-hit ray as proof that the movement controller is healthy.

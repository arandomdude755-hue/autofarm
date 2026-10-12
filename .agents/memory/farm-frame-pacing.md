---
name: Farm frame pacing
description: Performance constraints and validation lessons for Main Farm.
---

Main Farm still showed periodic client frame drops after the outer farm loop was throttled. A likely hot path was character collision suppression traversing and rewriting every character part on each Heartbeat; maintain it through one-time setup and instance/property events instead. Passing source checks does not prove live frame pacing.

**Why:** repeated full-character hierarchy scans and collision writes at frame frequency are avoidable frame-time work; the player reports BNN and Quantum did not show the same issue, so live testing is still needed to confirm the fix.

**How to apply:** when changing Main Farm movement or collision handling, avoid full-tree per-frame work, preserve collision restoration across stop/respawn, and verify performance with an in-game test.

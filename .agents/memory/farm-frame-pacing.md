---
name: Farm frame pacing
description: Performance constraints and validation lessons for Main Farm.
---

Main Farm still showed periodic client frame drops after the outer farm loop was throttled. A likely hot path was character collision suppression traversing and rewriting every character part on each Heartbeat; maintain it through one-time setup and instance/property events instead. Passing source checks does not prove live frame pacing.

After that full-character scan was removed, in-game testing reported the overall lag was mostly fixed but a hitch remained after each NPC kill. Target cleanup should discard per-model collision records without writing collision properties back to a defeated or detached NPC; restore collision for live targets and on farm shutdown.

Further testing isolated the remaining hitch to target acquisition: farming was smooth when a target was already available, but dropped frames while deciding which NPC to target. Name-target lookups and spawn-marker lookups should use normalized-name buckets rather than scanning every indexed model or marker per search.

**Why:** repeated full-character hierarchy scans, collision writes at frame frequency, and global target/spawn candidate scans are avoidable frame-time work; restoring many corpse parts can also add physics work on each kill. The player reports BNN and Quantum did not show the same issue, so live testing is still needed to confirm fixes.

**How to apply:** when changing Main Farm movement, collision handling, or target acquisition, avoid full-tree per-frame work, preserve collision restoration across stop/respawn, skip property writes for dead targets, use indexed candidate subsets, and verify performance with an in-game test.

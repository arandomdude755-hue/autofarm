---
name: Farm frame pacing
description: Performance constraints and validation lessons for Main Farm.
---

Main Farm still showed periodic client frame drops after the outer farm loop was throttled. A likely hot path was character collision suppression traversing and rewriting every character part on each Heartbeat; maintain it through one-time setup and instance/property events instead. Passing source checks does not prove live frame pacing.

After that full-character scan was removed, in-game testing reported the overall lag was mostly fixed but a hitch remained after each NPC kill. Target cleanup should discard per-model collision records without writing collision properties back to a defeated or detached NPC; restore collision for live targets and on farm shutdown.

Further testing isolated the remaining hitch to target acquisition: farming was smooth when a target was already available, but dropped frames while deciding which NPC to target. Name-target lookups and spawn-marker lookups should use normalized-name buckets rather than scanning every indexed model or marker per search.

The player tested the name-index optimization and reported that the hitch persisted. A separate unparented-instance fallback still enumerates a broad runtime list when normal NPC/spawn lookup has no result; move that fallback off the farm step and chunk it. Do not treat this change as confirmed until retested in-game.

Farm travel should pass through terrain and walls using direct movement with collision disabled; do not route around obstacles. When no target is available, hold the current airborne position and resume movement when a target or spawn destination is found.

**Why:** repeated full-character hierarchy scans, collision writes at frame frequency, global target/spawn candidate scans, and unparented-instance enumeration can all stall the client; restoring many corpse parts can also add physics work on each kill. Source checks cannot distinguish which path dominates on the player’s device.

**How to apply:** when changing Main Farm movement, collision handling, or target acquisition, keep travel direct and noclip rather than pathfinding, preserve airborne position during search gaps, avoid full-tree per-frame work, preserve collision restoration across stop/respawn, skip property writes for dead targets, use indexed candidate subsets, keep broad fallback discovery off the farm step, and verify performance with an in-game test.

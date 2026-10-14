---
name: Status tab data
description: Data-source and refresh rules for player, quest, and world-event status.
---

Status pages are observational. Reuse the existing validated QuestService state; do not infer quest acceptance from dialogue visibility or weaken catalog matching. Prefer local Workspace and Lighting signals. The Event Status page may use BNN's read-only `InfoLeviathan`, `1` and `CakePrinceSpawner`, `true` queries, rate-limited to 15 seconds while that page is selected. Never call `CakePrinceSpawner` without `true`, because BNN uses that call to open the portal. Derive server age and the four-hour legendary-item estimate from the oldest `_WorldOrigin.Locations.TimeIn` marker, preferring `Workspace:GetServerTimeNow()` and using BNN's `tick() - 25200` correction only as fallback; show unavailable if the clocks do not align.

**Why:** BNN uses these status sources, but its portal-opening call must not be reproduced by a status-only feature. Server-synchronized time avoids carrying a fixed local clock offset into normal calculations; fallback TimeIn math can still mismatch, and hidden-page polling adds work during farming.

**How to apply:** add status fields through StatusFeature and existing status-value rows; keep quest acceptance logic in QuestService, preserve unknown states, rate-limit remote reads, label event calculations as estimates, and avoid Heartbeat polling.

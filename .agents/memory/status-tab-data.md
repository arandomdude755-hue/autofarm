---
name: Status tab data
description: Data-source and refresh rules for player, quest, and world-event status.
---

Status & Server is observational. Reuse the existing validated QuestService state; do not infer quest acceptance from dialogue visibility or weaken catalog matching. Prefer local Workspace, Lighting, and HUD signals for event status. Do not invoke gameplay remotes just to populate the status page. Label source-derived calculations as estimates and show unavailable when their inputs are missing or unrecognized. Refresh periodic status only while the Status tab is visible.

**Why:** server queries can have side effects or return opaque state, while continuous hidden-page polling adds unnecessary work during farming. Some event timer inputs are only estimates from the reference sources.

**How to apply:** add new status fields through StatusFeature and the existing status-value rows; keep quest acceptance logic in QuestService, preserve unknown states, and avoid Heartbeat polling.

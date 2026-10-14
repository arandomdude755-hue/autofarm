---
name: Travel tab boundaries
description: User-approved scope for manual island and NPC travel.
---

Island and NPC travel are user-controlled toggles that turn off automatically on arrival; do not show a separate Cancel travel control. Offer only destinations in the current sea; the player changes seas manually. Do not add automatic sea travel or server hopping. Manual Travel-tab trips and Auto Farm must not move the character at the same time; gateway routing inside an active farm is part of that farm's own movement. NPC lookup should include live Workspace NPCs and valid current-sea ReplicatedStorage templates. For remote map gateways, approach the route's activation stand, retry bounded `requestEntrance` calls while confirming arrival by position, and do not treat a returned `nil` as success.

All long-distance travel initiated by farm modes or other tasks should use the same gateway planner and route executor as the Travel tab whenever a route is meaningfully shorter; otherwise retain normal movement as the fallback.

The user reports that defeating Tyrant of the Skies grants Tiki portal access, Feathered Visage is not guaranteed, and the “Liberator of the Sky” title is guaranteed. The title list is populated only while TitlesMenu is open; a missing entry while closed means unknown, not locked. For Tiki gateways, check Feathered Visage first, then use the title menu’s explicit unlocked/locked marker; a bounded hidden UI probe is preferred over a blind remote call.

**Why:** the user explicitly requested BNN-style travel toggles with automatic shutoff, broader NPC discovery, manual sea changes, no server hopping, no movement conflict with Auto Farm, and shared shortest-gateway routing for all travel tasks. They also confirmed remote activation alone no longer works and that the Vxeze-style approach is appropriate. The Tiki access and reward details are user-provided; runtime scans show the title entry disappears when TitlesMenu is closed, and the reference scripts only open the menu rather than verify title ownership. The user approved checking the title only after the item check and minimizing the menu probe’s visibility.

**How to apply:** keep destination lists current-sea-filtered, reject travel while Auto Farm is active, turn off the active travel toggle when movement ends or is cancelled, and stop travel before Auto Farm starts. Gateway activation should remain at the route stand and use a bounded retry window with observed-position confirmation. Treat a missing title entry while the menu is closed as unknown; check Feathered Visage first, then briefly probe TitlesMenu with its original visibility restored, and skip the Tiki route if title state remains unknown.

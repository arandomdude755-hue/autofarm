---
name: Travel tab boundaries
description: User-approved scope for manual island and NPC travel.
---

Island and NPC travel are user-controlled toggles that turn off automatically on arrival; do not show a separate Cancel travel control. Offer only destinations in the current sea; the player changes seas manually. Do not add automatic sea travel or server hopping. Travel and Auto Farm must not move the character at the same time. NPC lookup should include live Workspace NPCs and valid current-sea ReplicatedStorage templates.

**Why:** the user explicitly requested BNN-style travel toggles with automatic shutoff, broader NPC discovery, manual sea changes, no server hopping, and no movement conflict with Auto Farm.

**How to apply:** keep destination lists current-sea-filtered, reject travel while Auto Farm is active, turn off the active travel toggle when movement ends or is cancelled, and stop travel before Auto Farm starts.

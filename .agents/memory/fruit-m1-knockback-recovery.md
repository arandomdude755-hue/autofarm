---
name: Fruit M1 knockback recovery
description: Safety and efficiency rules for handling Fruit M1 knockback during mastery farming.
---

Do not anchor or forcibly reposition NPCs to counter Fruit M1 knockback. Do not reapply the tested player movement-hold recovery unchanged: it slowed Fruit M1 but did not prevent the player or NPC from flying.

For Fruit M1, do not add a synthetic per-tool cooldown. Let the game apply its own cooldown; keep the Mastery scan cadence and skill priority unchanged unless the user asks otherwise.

**Why:** The user tested the movement-hold attempt and asked to remove it because knockback continued while M1 became slower. A separate local cooldown also delayed retries, including requests that the game could have accepted. NPC physics are server-controlled, so anchoring or forcing their position could make them unresponsive.

**How to apply:** If revisiting Fruit M1 knockback, investigate a different approach and preserve attack cadence. Do not alter NPC physics, restore the failed hold, or throttle Fruit M1 using generic tool/skill cooldown values.

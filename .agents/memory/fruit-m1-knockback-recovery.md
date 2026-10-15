---
name: Fruit M1 knockback recovery
description: Safety and efficiency rules for handling Fruit M1 knockback during mastery farming.
---

Do not anchor or forcibly reposition NPCs to counter Fruit M1 knockback. After an issued Fruit M1, only pause player follow movement when the target shows a large displacement; continue M1 attempts while within the existing attack-distance guard, and shorten the pause when the target moves beyond that range so pursuit resumes promptly.

**Why:** NPC physics are server-controlled; local anchoring or velocity changes can desynchronize a target or make it unresponsive. A brief, conditional movement hold addresses the chase loop without changing target physics or suppressing in-range attacks.

**How to apply:** Keep this recovery scoped to Fruit M1 until in-game testing confirms it preserves damage rate. Do not extend it to fruit skills or ordinary farming unless a separate test shows those paths need it.

---
name: Low-health retreat
description: User-approved behavior for the optional low-health rise feature.
---

When enabled, the retreat should rise vertically from the player's current position, hold them at the configured altitude while health is below 80%, pause attacks and other movement during that time, and resume the interrupted task once health reaches 80%. Do not anchor the character.

**Why:** the user wants the character to remain safely elevated for the full recovery window, not return to farming immediately after the ascent.

**How to apply:** keep the shared movement service as the owner of the retreat and release it at 80% health so the preserved movement goal can continue.

---
name: Player-facing errors
description: How the hub should explain blocked or failed actions to players.
---

When two features cannot run together, block the second action and explain in plain language which active feature must be turned off. Show errors in a brief bottom-right notification styled like the hub; do not expose developer-oriented wording in the notification.

**Why:** the user asked that feature conflicts be explained clearly to players rather than only appearing in the status line.

**How to apply:** add the conflict check where the second action starts, leave its toggle off, and show a themed bottom-right error with a concrete next step.

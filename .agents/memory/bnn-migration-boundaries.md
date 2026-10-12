---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

For the Tiki Outpost event phase, limit migration to detecting the four Eye parts and approaching available Tree objects. Do not automate broad skill use, Skull Guitar remotes, purchases, or server hopping.

**Why:** the BNN source relies on executor-specific persistence APIs that are not portable, and the user approved only Tiki event detection/approach—not its multi-weapon skill automation or item/server actions.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI. Ask before adding Tiki skill or item automation.

---
name: BNN migration boundaries
description: Project decisions for migrating Banana Cat Hub farming features and settings.
---

Migrate BNN features in functional slices, and add settings alongside the feature that uses them. Use this project’s configuration path rather than copying BNN executor filesystem persistence. Do not expose BNN controls until their behavior is implemented.

**Why:** the BNN source relies on executor-specific persistence APIs that are not portable to this project, and a visible but inactive control would imply functionality that is not present.

**How to apply:** for future BNN farming migrations, keep the tested Level Farm path intact, implement each mode with its related settings, and keep unimplemented modes out of the UI.

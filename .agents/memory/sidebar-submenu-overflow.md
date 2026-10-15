---
name: Sidebar submenu overflow
description: Keep expanded child rows visible in the sidebar without tab-specific offsets.
---

When any expandable sidebar tab opens, automatically scroll the sidebar enough to reveal its child rows if they extend below the visible area. Keep this behavior generic; do not hardcode a tab name or fixed offset.

**Why:** The user wants fewer manual scrolls when switching between nested pages, including Settings and future expandable tabs.

**How to apply:** Use shared navigation layout and viewport bounds to detect overflow whenever a nested page is selected.

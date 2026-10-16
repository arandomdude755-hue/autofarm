---
name: Stack Farming priority rules
description: User-defined scheduling for Stack Farming jobs alongside Main Farming.
---

Stack Farming may interrupt Main Farming and resume it after completion, but must wait for any active non-Main-Farming task (including travel and future feature tabs) to finish. Stack jobs preserve FIFO order; within a consecutive batch of fruit tasks, order pickups by the shortest gateway-aware route. Enabled Stack Farming tasks also run when Main Farming is off, provided no other foreground task owns the worker. Boss preparation is a queued stack job: only prepare when the user already holds the required summon item, and do not let later jobs overtake a preparation already in progress. Indra/Dough priority toggles require their parent boss toggle and are mutually exclusive. Server-hop jobs wait behind active and earlier queued Stack Farming jobs. Chest farming belongs in Farming Other, not Stack Farming, because it is continuous and conflicts with other farming.

**Why:** The user clarified that Stack Farming should preempt only Main Farming. Other current or future features must finish their active task before a stack job starts; module-specific priority checks would make this fragile as tabs are added.

**How to apply:** Use a shared task coordinator for Stack Farming, travel, and future task-based tabs. Each feature should declare whether it owns an active task; defer new stack work behind any active non-Main-Farming task, while allowing it to interrupt Main Farming. Keep Stack jobs FIFO, optimize fruit batches internally without moving them ahead of an earlier non-fruit job, and reuse shared movement/combat services.

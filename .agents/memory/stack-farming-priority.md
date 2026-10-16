---
name: Stack Farming priority rules
description: User-defined scheduling for Stack Farming jobs alongside Main Farming.
---

Cake Prince and spawned-fruit tasks interrupt Main Farming and resume it after completion. Preserve spawn order between different task types; within a consecutive batch of fruit tasks, order pickups by the shortest gateway-aware route. Enabled Stack Farming tasks also run when Main Farming is off. Boss preparation is also a queued stack job: only prepare when the user already holds the required summon item, and do not let later jobs overtake a preparation already in progress. Indra/Dough priority toggles require their parent boss toggle and are mutually exclusive. Stack Farming server-hop jobs must wait behind active and earlier queued stack jobs; hops triggered by other farm modes or travel may interrupt those modes. Do not add server hopping to Stack Farming unless requested. Chest farming belongs in Farming Other, not Stack Farming, because it is continuous and conflicts with other farming.

**Why:** The user wants spawned priorities handled without competing farm routines, wants Stack Farming available independently of Main Farming, and considers continuous chest farming incompatible with interruption-style stack jobs. Rare summon items are opportunistic; searching or farming for them would turn a stack job into a competing main farm.

**How to apply:** Route future stack jobs and boss preparation through the shared worker and FIFO queue; optimize fruit batches internally without moving them ahead of an earlier non-fruit job. Keep manual-travel conflict checks and do not introduce a second movement/combat loop.

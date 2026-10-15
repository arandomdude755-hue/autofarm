---
name: Stack Farming priority rules
description: User-defined scheduling for Stack Farming jobs alongside Main Farming.
---

Cake Prince and spawned-fruit tasks interrupt Main Farming, run one at a time in the order they appeared, and resume Main Farming after completion. Enabled Stack Farming tasks also run when Main Farming is off. Do not add server hopping to Stack Farming unless requested.

**Why:** The user wants spawned priorities handled without competing farm routines, and wants Stack Farming available independently of Main Farming.

**How to apply:** Route future stack jobs through the shared worker and FIFO queue; preserve manual-travel conflict checks and do not introduce a second movement/combat loop.

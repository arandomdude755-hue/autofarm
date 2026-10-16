---
name: Server-hop handshake
description: Server discovery and teleport behavior for this Roblox game.
---

Use the game's server-browser remote for both listing candidate instances and requesting a join. Reference hubs invoke it with a page number to list servers and with `"teleport", jobId` to join. Calling `TeleportService:TeleportToPlaceInstance` directly from the client produced Roblox's “Cannot teleport without a valid teleport token” rejection. External public-server HTTP requests also returned errors in testing.

**Why:** The server-browser remote performs the game's expected teleport handshake; a client-side direct place-instance call does not provide the required token.

**How to apply:** Keep server lookup and joining on the server-browser remote. Avoid adding a direct `TeleportToPlaceInstance` fallback unless its token requirements are independently solved and verified.

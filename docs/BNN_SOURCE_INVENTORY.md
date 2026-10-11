# BNN source inventory and UI-shell boundary

Source inspected: `attached_assets/3nn_main.lua_(1)_1791658701991.txt` (19,646 lines; 621,580 bytes). This is a static-source inventory, not a runtime validation.

## Organization visible in the source

The file is a large, mostly monolithic client script. It starts with persisted settings and runtime/bootstrap checks, defines shared helpers and feature functions, then builds UI pages and connects controls to callbacks. Main pages are created at these source lines:

| Page | Line |
| --- | ---: |
| Shop | 152 |
| Status And Server | 560 |
| LocalPlayer | 1910 |
| Setting Farm | 4368 |
| Hold and Select Skill | 4661 |
| Farming | 4710 |
| Stack Farming | 5627 |
| Farming Other | 6854 |
| Fruit and Raid, Dungeon | 8716 |
| Sea Event | 9783 |
| Upgrade Race | 12352 |
| Get and Upgrade Items | 15250 |
| Volcano Event | 17318 |
| ESP | 18338 |
| PVP | 18665 |
| Tab Webhook | 18854 |
| Setting | 19255 |

The broad feature families include shops, player utilities, quest and level farming, mastery/material farming, raids and dungeons, sea events, race progression, item upgrades, ESP, PVP, server utilities, webhooks, and settings. These are groupings inferred from page/section names and function names; they are not evidence that each feature works in a current game build.

## UI framework and callback pattern

At lines 146–152 the source downloads and executes a separate UI library from `https://raw.githubusercontent.com/obiiyeuem/vthangsitink/refs/heads/main/zzzz.lua`, then calls `A.CreateMain`, `Main.CreatePage`, and `Page.CreateSection`. Controls such as `CreateButton`, `CreateToggle`, `CreateDropdown`, and `CreateSlider` are configured with callbacks. For example, farm controls are created around lines 4711–4792; their callbacks save values, and some also start or gate other work. A player-page button at lines 1911–1920 directly calls movement cancellation. Thus presentation controls and feature behavior are coupled through callback closures and shared globals rather than isolated controller modules.

The downloaded UI library is not present in this repository, so its implementation, mobile behavior, lifecycle guarantees, and exact control contracts cannot be verified from the BNN file alone.

## Dependencies visible in the source

- **Roblox runtime:** `Players`, `ReplicatedStorage`, `Workspace`, `RunService`, `TweenService`, `UserInputService`, `TeleportService`, `HttpService`, GUI services, character objects, and game-specific replicated modules.
- **Shared/global state:** many script-wide globals (`Settings`, `CommF`, `Main`, page/section values, helper functions) and `getgenv()` entries are referenced across distant feature blocks.
- **Game-specific modules/remotes:** examples include `ReplicatedStorage.Quests`, `GuideModule`, `Modules.CombatUtil`, `Modules.Net`, `NPCManager`, `CommF_`, `RegisterAttack`, `RegisterHit`, and `__ServerBrowser`. Their server-side behavior and compatibility are not established by client source.
- **Executor-specific APIs:** early setup uses `getgenv`, `loadstring(game:HttpGet(...))`, debug upvalue APIs, executor request functions, filesystem APIs such as `readfile`/`writefile`/`makefolder`, and virtual input. Additional features use clipboard or server-listing endpoints.
- **Dynamic code:** the UI library is fetched at line 150; other dynamically fetched/loaded code and endpoint responses are not available as part of this repository snapshot.

Static inspection confirms that calls are written in the client source. It cannot confirm their server responses, permissions, current game compatibility, or resulting effects.

## What can be separated safely

The tab list, theme tokens, control descriptions, navigation, local status text, UI-only settings, and lifecycle/disposal can be implemented independently using Roblox GUI primitives. Pure calculations and feature controllers can later be separated behind explicit adapters, but the BNN callbacks cannot be copied as isolated features without also resolving their globals, dynamic dependencies, game modules, remotes, and side effects.

The modular UI shell was prototyped separately from this standalone test. That prototype uses a central config/state module, a Roblox compatibility adapter, a UI module, and an independently initialized/cleaned feature manager with harmless placeholders. The standalone script below does not depend on those modules and does not invoke BNN, game remotes, movement, combat, or farm code.

## Proposed integration boundary

```text
StarterPlayerScripts/CustomHub.client.lua
  -> ReplicatedStorage/CustomHub
       -> Config, State, Compatibility, UI, FeatureManager
            -> Features/PlaceholderFeatures
```

Feature modules should be reviewed independently before they are added to the manager. Each future integration should declare its required adapters, initialize/cleanup behavior, status/error reporting, and verified inputs/outputs. No BNN feature is treated as authorized or compatible merely because it appears in the reference.

## Standalone mobile client test

Use `tests/Standalone_CustomHub_UI_Test.client.lua` as the practical UI-only test entrypoint. It is one self-contained LocalScript: it does not call `require`, load code from a URL or local path, or depend on the Rojo modules. Copy the entire file into a LocalScript-capable client test host you control and run it. It creates the shell under `Players.LocalPlayer.PlayerGui`.

The script prints client-side PASS/FAIL checks for mounting, the five tab controls and their selected indicators, preview/settings state, placeholder actions, status rendering, scrolling overflow, toggle spacing, repeated mounting, and connection/UI cleanup. Its visible status summarizes the automated checks. It also prints a separate `MANUAL` reminder to tap each tab and Close and inspect text fit, contrast, and scrolling on the target phone. Those visual/touch checks cannot be proved by the script.

Tap **Close** to disconnect the UI's event connections, destroy the ScreenGui, and remove the local cleanup registry. Rerunning the script first invokes the previous run's local `BindableFunction` cleanup callback, then mounts one replacement UI. The registry is a client-local Roblox Instance; it is not a remote or executor API.

This file is source, not an injection or loader mechanism. A normal player client does not provide a built-in way to create arbitrary LocalScripts in a published experience; the target game or test environment must already provide an authorized way to run client LocalScript source. No Studio Command Bar or manual ModuleScript `require` is needed when such a host exists.

The current Rojo mapping packages the standalone script directly into `StarterPlayerScripts`; it has no ModuleScript dependency. If the modular prototype is brought into this project later, Rojo must package its modules into the DataModel before a client entrypoint can `require` them. `require` does not load arbitrary repository files.

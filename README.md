# Word Hunt

Word Hunt is a Roblox puzzle game with fresh server-generated boards and a fully scripted, cross-device interface. The internal `WordSearchRevamp` names remain unchanged so existing remotes and saved data stay compatible. The client renders the board and handles input, while the server owns puzzle paths, round validation, progression, rewards, and saved data.

The current revamp supports:

- 1,000 Classic levels across Animals, Food, Nature, Roblox, Space, and Expert chapters
- Quick Play and a pinned UTC Daily word-list rotation with a fresh grid
- Mouse, touch, keyboard, and gamepad board selection
- Stars, XP ranks, coins, hints, achievements, and daily streaks
- A responsive white-glass HUD over a softly blurred menu sky, with a global navigation drawer and a clean open-letter board with persistent colored word trails
- A short replayable, interactive tutorial for mouse, touch, keyboard, and controller
- A paginated chapter browser that keeps only 30–48 of the 1,000 level buttons live at once
- Continue, Daily, pause/restart, result/best-time, achievement, purchase-confirmation, toast, and error flows built from one shared UI system
- Reduced motion, high contrast, and colorblind settings
- Server-backed achievement, shop, daily-reward, purchase, and cosmetic-equipping screens
- Confirmed hint spending plus live equipped themes, word-trail palettes, menu backgrounds, and board styles

Zen mode is supported by the server contract but is not exposed on the main menu. Time Attack is not implemented.

## Repository layout

All game source is stored under `src/`:

- `src/client/GameController.local.luau` - client entrypoint and view/remote orchestration
- `src/client/ui/` - the modular UI application, screens, reusable components, navigation, modals, notifications, responsive layout, theme, and image-asset registry
- `src/client/revamp/` - retained non-visual input, animation, audio, and environment controllers
- `src/server/bootstrap/ServerBootstrap.server.luau` - server entrypoint and remote wiring
- `src/server/content/` - the private level catalog and authored word paths
- `src/server/puzzle/` - deterministic board generation and validation
- `src/server/data/` - persistent profiles, leases, normalization, and economy mutations
- `src/server/services/` - authoritative round, reward, daily, economy, and rate-limit services
- `src/server/tests/PuzzleEngineTests.luau` - content, generator, validator, remote, and economy tests
- `src/shared/` - replicated configuration and shared types
- `src/REVAMP_HANDOFF.md` - detailed architecture, datastore, content, and Studio release notes

## Development workflow

This checkout contains source rather than a Rojo project. Sync or copy the folders into the existing Roblox place with this runtime hierarchy:

```text
ReplicatedStorage
  shared
ServerScriptService
  server
StarterPlayer
  StarterPlayerScripts
    client
```

The lowercase `ReplicatedStorage.shared` name and the nested folder names are required by the runtime imports. Keep exactly one active `client/GameController` LocalScript and one `server/bootstrap/ServerBootstrap` Script.

The server creates `ReplicatedStorage.WordSearchRevampRemotes`. The client builds `WordSearchUI` at runtime, so a legacy authored HUD or the retired `WordSearchRevampHUD` should not run alongside it. Existing sounds may be reused from `SoundService/SFX` and `SoundService/Music`; explicit image and sound IDs remain configurable placeholders in `src/shared/config/GameConfig.luau`.

## Validation

In Roblox Studio, the server bootstrap automatically runs the puzzle suite. It can also be invoked manually:

```luau
require(game.ServerScriptService.server.tests.PuzzleEngineTests).Run()
```

Before publishing, test with at least two Studio clients and cover the full first-time tutorial, desktop, phone/tablet emulation, gamepad navigation, drawer close paths, round replay, Daily rollover, pause/hints, shop purchases/equips, settings, DataStore failure, menu-to-game camera restoration, and shutdown saving. Source inspection cannot verify Studio-authored hierarchy, assets, live DataStores, or published-service behavior.

## Persistence and security

Production data uses `WordSearchRevamp_v1`, schema version 1, with leased sessions, `UpdateAsync` retries, autosave, player-removal release, and bounded shutdown saving. Studio uses memory-only profiles and does not read or overwrite production data.

Canonical paths never replicate to clients. Selection geometry, active round identity, unlocks, hint spending, completion, rewards, and economy changes are validated server-side. Do not move these decisions to the client, commit credentials, or enable placeholder Developer Product entries without real IDs and receipt handling.

Read `AGENTS.md` and `src/REVAMP_HANDOFF.md` before changing gameplay, persistence, remotes, UI structure, or level content.

# Word Search

Word Search is a Roblox puzzle game with fresh server-generated boards and a fully scripted, cross-device interface. The client renders the board and handles input, while the server owns puzzle paths, round validation, progression, rewards, and saved data.

The current revamp supports:

- 120 Classic levels across Animals, Food, Nature, Roblox, Space, and Expert chapters
- Quick Play and a pinned UTC Daily word-list rotation with a fresh grid
- Mouse, touch, keyboard, and gamepad board selection
- Stars, XP ranks, coins, hints, achievements, and daily streaks
- Responsive layouts, reduced motion, high contrast, and colorblind settings
- Server-side daily rewards, coin purchases, and cosmetic ownership APIs

Zen mode is supported by the server contract but is not exposed on the main menu. Shop and daily-login reward APIs are also present without dedicated client screens. Time Attack is not implemented.

## Repository layout

All game source is stored under `src/`:

- `src/client/GameController.local.luau` - client entrypoint and view/remote orchestration
- `src/client/revamp/` - scripted UI, input, animation, audio, environment, and responsive theme modules
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

The server creates `ReplicatedStorage.WordSearchRevampRemotes`. The client builds `WordSearchRevampHUD` at runtime, so a legacy authored HUD should not run alongside it. Existing sounds may be reused from `SoundService/SFX` and `SoundService/Music`; explicit image and sound IDs remain configurable placeholders in `src/shared/config/GameConfig.luau`.

## Validation

In Roblox Studio, the server bootstrap automatically runs the puzzle suite. It can also be invoked manually:

```luau
require(game.ServerScriptService.server.tests.PuzzleEngineTests).Run()
```

Before publishing, test with at least two Studio clients and cover desktop, phone/tablet emulation, gamepad navigation, round replay, Daily rollover, pause/hints, settings, DataStore failure, and shutdown saving. Source inspection cannot verify Studio-authored hierarchy, assets, live DataStores, or published-service behavior.

## Persistence and security

Production data uses `WordSearchRevamp_v1`, schema version 1, with leased sessions, `UpdateAsync` retries, autosave, player-removal release, and bounded shutdown saving. Studio uses memory-only profiles and does not read or overwrite production data.

Canonical paths never replicate to clients. Selection geometry, active round identity, unlocks, hint spending, completion, rewards, and economy changes are validated server-side. Do not move these decisions to the client, commit credentials, or enable placeholder Developer Product entries without real IDs and receipt handling.

Read `AGENTS.md` and `src/REVAMP_HANDOFF.md` before changing gameplay, persistence, remotes, UI structure, or level content.

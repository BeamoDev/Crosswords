# Word Hunt

Word Hunt is a Roblox word-search game with a 150-board Classic path plus Themed, Freeplay, Backwards, Fog, OneLife, Mega, Daily, and Duel modes. The client presents authored Desktop/Mobile interfaces and responsive board input; the server independently validates puzzle actions and owns rewards, progression, persistence, receipts, Daily claims, and Duel results.

## Current gameplay rules

- Normal puzzles are untimed. Solve duration never causes a loss or changes stars, score, or puzzle-piece rewards.
- A completed normal board awards 3 stars with no hints, 2 stars with one hint, and 1 star with two or more hints.
- Classic Board 1 is the onboarding board: a 4x4 grid containing only the two target words `CAT` and `DOG`, placed eastward.
- Daily reset and session playtime-reward countdowns are meta schedules, not puzzle deadlines.
- Duel may record race duration because both players compete on the same puzzle.

## Source layout

The implementation is consolidated into 35 runtime Luau modules—13 client, 11 server, and 11 shared—plus one pure puzzle test module.

```text
src/
  client/
    ClientBootstrap.local.luau
    controllers/        GameController, BoardController, ProgressionController, InterfaceController
    features/           Duels, Rewards, Social, Admin
    systems/            Input, Camera, Audio, Device
  server/
    ServerBootstrap.server.luau
    services/           GameService, ProgressionService, DuelService, RewardService, SocialService
    data/               DataService, DataSchema
    systems/            Analytics, Moderation, Operations
  shared/
    config/             GameConfig, ProgressionConfig
    content/            PuzzleCatalog, WordBank
    network/            NetworkContract
    puzzle/             PuzzleEngine, PuzzleGenerator, PuzzleTypes, PuzzleValidator, PuzzleTests.spec
    ui/                 UIEffects (required by the authored HUD FX LocalScript)
    utility/            Utility
```

`ClientBootstrap.local.luau` and `ServerBootstrap.server.luau` are the only executable entrypoints. The other files are ModuleScripts. See `ARCHITECTURE.md` for ownership, dependencies, remotes, persistence, and deployment notes.

## Security and persistence

- `DataService` is the only owner of saved player data and the in-server session cache.
- Production persistence remains `WordSearchData_v1`, key prefix `player_`, data version 11.
- The server regenerates expected puzzles and validates submitted words and exact paths. Client-reported rewards, stars, clears, progression, or receipt outcomes are never trusted.
- `NetworkContract` bounds remote payload depth, size, word/path lengths, allowed actions, board modes, and per-action rates.
- Developer Product receipt grants remain idempotent. Retired timer products are compatibility-only and settle as hints; no client flow sells or consumes puzzle time.
- Webhook URLs must remain private ServerStorage configuration and must never be committed.

## Development boundary

This repository has no Rojo project and does not contain every Studio-authored interface or world instance. Preserve lowercase `ReplicatedStorage.shared`, the existing authored `ReplicatedStorage.Interfaces` hierarchy, and the legacy-compatible remote names when synchronizing source.

Local checks can verify text, imports, configuration invariants, and repository hygiene. They cannot prove Studio hierarchy, ModuleScript/LocalScript placement, authored UI compatibility, Roblox service behavior, DataStores, assets, device layout, or published-game behavior. Run those checks in Roblox Studio before release, but do not describe them as completed unless they were actually performed.

The pure shared contract suite can run without Studio when Lune is available:

```powershell
lune run src/shared/puzzle/PuzzleTests.spec.luau
```

It covers deterministic generation, Board 1, definition/path validation, completion, scoring, Daily identity, hint-based stars, timed-reward configuration, remote payload bounds, and action throttling.

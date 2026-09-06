# Word Hunt source architecture

This document describes the selected 150-board source tree. It replaces the obsolete handoff for the unrelated 1,000-level revamp.

## Dependency direction

```text
ClientBootstrap -> client controllers/features/systems -> shared config/content/network/puzzle/utility
ServerBootstrap -> server services/data/systems -> shared config/content/network/puzzle/utility
shared modules -> shared modules only
```

Client modules never require server modules. Server modules never require client modules. The two bootstraps own runtime wiring; feature and service modules expose focused APIs.

## Client ownership

- `ClientBootstrap.local.luau` starts the client exactly once.
- `controllers/GameController.luau` owns shared client state, remote bootstrap, mode/view coordination, and composition.
- `controllers/BoardController.luau` owns puzzle rendering, selection feedback, hint presentation, resume flow, scoring display, and completion flow. Shared path/score helpers come from `PuzzleEngine`.
- `controllers/ProgressionController.luau` owns stats, settings, shop, rewards, and leaderboard presentation.
- `controllers/InterfaceController.luau` selects/clones the authored Desktop or Mobile interface, resolves its controls, and owns reusable GUI helpers, buttons, transitions, Classic-level visuals, and effects.
- `features/Duels.luau` owns Duel matchmaking and race presentation.
- `features/Rewards.luau` owns session playtime-reward presentation plus board-result and Classic-level-selection flows.
- `features/Social.luau` owns idle-rejoin and group-intro presentation.
- `features/Admin.luau` owns admin UI only; authority remains on the server.
- `systems/Input.luau`, `Camera.luau`, `Audio.luau`, and `Device.luau` own cross-mode input, camera, music, and device/orientation behavior respectively.

## Server ownership and startup

`ServerBootstrap.server.luau` initializes dependencies in this order: remote creation, player lifecycle connections, DataService autosave, leaderboards, Duel, playtime rewards, and live operations. Shutdown stops autosave, flushes leaderboards, and saves loaded profiles.

- `data/DataService`: session ownership, snapshots, DataStore retries, autosave, release, receipt history, player mirrors, and saved board state.
- `data/DataSchema`: profile defaults, version migration, normalization, mode result/streak schemas, and timed-reward claim shape.
- `GameService`: regenerates canonical puzzles, sanitizes resume state, and validates word paths, hints, clears, and Daily identity.
- `ProgressionService`: applies accepted puzzle actions, stars, puzzle pieces, Classic unlocks, and loss outcomes.
- `RewardService`: owns hint spending, Daily/group/gift/playtime rewards, settings, purchases, and receipt grants.
- `DuelService`: challenge, matchmaking, shared-board race state, progress, timeout/leave resolution, and Duel rewards.
- `SocialService`: ordered-store leaderboard cache, dirty writes, refresh, and bounded client refresh requests.
- `systems/Analytics`: funnel, completion, Duel, and economy events.
- `systems/Moderation`: admin authorization, commands, and menu actions.
- `systems/Operations`: idle rejoin, day/night cycle, and optional protected outbound reports using private runtime configuration.

## Shared ownership

- `GameConfig`: group, products, leaderboard, hint-price, and puzzle-piece economy settings.
- `ProgressionConfig`: UTC Daily identity, gift milestones, hint-based star rules, and session playtime rewards.
- `PuzzleCatalog`: the indexed 150-board Classic catalog plus mode and themed puzzle collections.
- `WordBank`: reusable word data kept separate from catalog-building logic.
- `NetworkContract`: remote names, legacy aliases, action allowlist, payload schemas, and rate limits.
- `PuzzleGenerator`: deterministic grid generation and mode-aware definition building.
- `PuzzleEngine`: small pure path, completion, and score helpers used by the client.
- `PuzzleTypes`: shared structural types for cells, definitions, generated puzzles, and resumable board state.
- `PuzzleValidator`: server-side normalization, path bounds/matching, and definition validation.
- `PuzzleTests.spec`: opt-in checks for generation, Board 1, path/completion rules, Daily identity, stars, payload validation, and action throttling.
- `ui/UIEffects`: the shared button animation implementation used by both `InterfaceController` and the Studio-authored `HUD.FX` LocalScript. Its replicated path is a live authored-UI compatibility boundary.
- `Utility`: instance creation, deep cloning/default merging, and safe shared-config resolution.

## Remote surface

The main folder is `ReplicatedStorage.WordSearchBackendRemotes`:

- `GetBootstrap` (`RemoteFunction`): returns the current sanitized snapshot.
- `TrackAction` (`RemoteEvent`): accepts only allowlisted, bounded puzzle/funnel actions.
- `StateUpdated` (`RemoteEvent`): server-to-client sanitized snapshots.
- `UseHint` (`RemoteFunction`): validates and spends a server-owned hint.

Legacy-compatible endpoints remain under `ReplicatedStorage.Remotes.Events` and `Functions` for purchases, Daily/group/gift/playtime rewards, settings, admin, leaderboard, Duel, and idle rejoin flows. Their names are centralized in `NetworkContract`; Duel owns its legacy remote construction because it owns that protocol.

## Timer and reward policy

There is no normal-puzzle countdown, timeout loss, time extension, freeze item, speed-based star threshold, or speed reward. Clear duration may be recorded for diagnostics/analytics only. Stars depend only on completion and hints used. Puzzle pieces depend on grid/mode, hint/reset penalties, and clean-play bonuses.

Retired timer inventory fields are removed during data-version-11 normalization. Existing paid receipts for retired timer products remain settleable as hint grants, after which the receipt ID is recorded.

## Persistence invariants

- Store: `WordSearchData_v1`; keys: `player_<UserId>`; current version: 11.
- Only `DataService` accesses the profile DataStore or mutable session table.
- Normalize defaults, migrations, snapshots, mirrors, receipt caps, and board-state sanitization together.
- Do not mark unknown receipts as granted. Mark supported receipts only after the corresponding mutation succeeds.
- Never trust a client-provided board, word, path, clear, reward, star count, unlock, or currency balance.

## Validation boundary

Source checks should cover the 35-runtime-module count, entrypoint uniqueness, missing-module references, Board 1, timer/star invariants, DataStore/version/receipt compatibility, remote schemas/rates, merge markers, secrets, binary place files, and `git diff --check`. `shared/puzzle/PuzzleTests.spec.luau` can run under Lune without opening Studio.

Studio-only release checks still include exact script class/location, lowercase shared hierarchy, authored Desktop/Mobile UI bindings, all input types, every mode, resume/leave, Daily rollover, playtime rewards, purchases and receipt replay, admin authorization, two-player Duel, DataStore denial/retry, respawn, autosave, and shutdown. Source inspection is not evidence that these runtime checks passed.

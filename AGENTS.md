# Word Search repository instructions

These instructions apply to the entire repository.

## Current source authority (2026-09-04)

- The user explicitly selected the current `src/` tree as the source to change.
- This checkout is the 150-board Word Hunt implementation, not the unfinished 1,000-level modular revamp previously described here.
- `README.md` and `src/REVAMP_HANDOFF.md` still describe that different revamp and are historical references only. Do not use them to infer current files, remotes, persistence, modes, UI, or release state.
- Make repository changes only unless the user explicitly asks for Roblox Studio synchronization or publishing. Never claim a source edit has been tested in Studio or in the published place without direct evidence.
- Preserve unrelated dirty-worktree changes and Studio-authored assets that are not represented in this repository.

## Repository and runtime boundaries

- This checkout has no Rojo project. Do not introduce Rojo, Wally, Rokit, generated places, or dependency lock files unless the workflow is intentionally changed.
- Preserve exact folder names and casing. Shared imports expect lowercase `ReplicatedStorage.shared`.
- `GameController.local.luau` currently refuses to run when it is a descendant of `StarterPlayerScripts`. Do not relocate the active LocalScript or guess the live hierarchy without inspecting the synchronized Studio place.
- The client chooses `ReplicatedStorage.Interfaces.Desktop` or `Mobile`, clones it to `PlayerGui.HUD`, and then binds the authored hierarchy. Do not add a second HUD.
- Keep exactly one active `GameController` LocalScript and one `ServerBootstrap` Script.
- The server creates `ReplicatedStorage.WordSearchBackendRemotes` plus the legacy-compatible `ReplicatedStorage.Remotes.Events` and `Functions` endpoints.

## Current architecture

- `src/client/GameController.local.luau`: client entrypoint, shared state, modes, remote bootstrap, view flow, audio, and controller composition.
- `src/client/gameplay/BoardRuntime.luau`: deterministic local board rendering, selection input, hints, animations, resume flow, scoring preview, completion, and Duel presentation.
- `src/client/gameplay/ClassicLevels.luau`: Classic level selector state and rendering helpers.
- `src/client/ui/`: bindings for the authored Desktop/Mobile HUD, menus, summaries, meta screens, playtime rewards, and Duel UI.
- `src/client/input/InputBindings.luau`: mouse, touch, and gamepad drag lifecycle.
- `src/server/bootstrap/ServerBootstrap.server.luau`: server entrypoint, remotes, receipts, lifecycle, and service wiring.
- `src/server/services/gameplay/BoardValidationService.luau`: regenerates boards server-side and validates word paths, hints, resumable state, and clears.
- `src/server/services/gameplay/ProgressionService.luau`: applies validated words, outcomes, stars, puzzle-piece rewards, and progression.
- `src/server/services/gameplay/DuelService.luau`: matchmaking and competitive race lifecycle.
- `src/server/data/PlayerDataStore.luau`: sole persistent-data owner, normalization, snapshots, session ownership, and saving.
- `src/server/services/meta/`: hints, daily/group/gift rewards, playtime rewards, and leaderboards.
- `src/shared/content/Levels.luau`: deterministic 150-board Classic catalog generated across six difficulty packs.
- `src/shared/board/`: shared definition and board generation used independently by client and server.
- `src/shared/progression/StarRules.luau`: durable per-board star-slot resolution and hint-based star awards.
- `src/shared/config/`: remote names, hint products, puzzle-piece economy, and playtime-reward configuration.

## Normal-puzzle timer policy

- Classic, Themed, Freeplay, Backwards, Fog, OneLife, Mega, and Daily are untimed. A player never loses, earns fewer rewards, or receives fewer stars because they solve slowly.
- Do not restore a countdown-to-loss, time extension, timer freeze, speed multiplier, speed-based star threshold, or speed-based puzzle-piece bonus to normal puzzles.
- Do not sell gameplay time. The retired +2 Minutes and Freeze Timer Developer Product IDs must never be prompted by the client or exposed as usable inventory.
- Data version 11 converts each retired timer item into one hint once, removes the retired fields from snapshots and player mirrors, and keeps a server-only receipt compatibility mapping so already-paid pending receipts can settle as hints.
- The short 3-2-1 board-introduction animation is presentation, not a solve deadline. Daily reset countdowns and playtime reward countdowns are meta systems. Duel may measure race duration because players compete on the same board.
- Internal clear duration may be retained for anti-abuse diagnostics and aggregate analytics, but must not influence normal-puzzle wins, stars, score, or puzzle-piece rewards.

## Stars and progression

- A completed normal board awards 3 stars with no hints, 2 stars with one hint, and 1 star with two or more hints.
- An incomplete or lost board awards 0 stars. OneLife may still record a loss after an invalid selection.
- Star progress stores the best result for each mode/pack/entry slot. Update client preview and server authority together whenever star rules change.
- Classic contains 150 sequential boards. Board 1 is an intentional onboarding board and must remain exactly two familiar words, `CAT` and `DOG`, on a 4x4 grid with only eastward placement.
- Every board after Board 1 continues to use the tier generator unless the content design is changed intentionally.
- Server validation regenerates the expected board and checks the claimed word path. Never trust a client-reported clear, hint use, reward, star count, or progression value.

## Persistence and receipts

- Production persistence uses `WordSearchData_v1`, keyed as `player_<UserId>`; the current data version is 11.
- `PlayerDataStore` alone owns load, normalization, snapshots, session tokens, saves, releases, and player data mirrors.
- When changing saved data, update defaults, normalization/migration, snapshots, mirrors, and all readers together.
- Preserve processed-receipt idempotency. Unknown Developer Product receipts must remain retryable; supported hint products and retired-product conversions must mark a receipt only after applying the grant.
- Do not read, overwrite, delete, or migrate production data outside the explicit migration code without the user's approval.

## Gameplay and security

- Supported modes are Classic, Themed, Freeplay, Backwards, Fog, OneLife, Mega, Daily, and Duel.
- Board definitions and generation code replicate to the client for presentation, but server validation independently rebuilds the board and validates exact paths before progression.
- Keep remote action allowlists and throttles server-side. A client sends bounded intent; the server owns hints, clears, stars, puzzle pieces, progression, Daily completion, Duel results, and receipts.
- Keep Daily identity deterministic and reject stale Daily resume state after rollover.
- Never commit credentials, webhook secrets, production exports, local place files, or certificates.

## Client and accessibility

- Review mouse, touch, keyboard, and gamepad behavior together for input or focus changes.
- Preserve arithmetic cell hit-testing, active-gesture input tracking, board path visuals, and centralized interaction locks.
- Use `GuiButton.Activated` for cross-device actions.
- Preserve Desktop/Mobile template selection and validate both orientations and controller focus in Studio after UI changes.
- Optional UI or sound instances must degrade safely when missing.

## Validation and release claims

- Run available local syntax/static checks after Luau edits and inspect changed files for stale imports, deleted-module references, merge markers, credentials, and client/server contract drift.
- This source currently has no checked-in automated Studio test suite. Validation in this checkout is static unless a Studio session is actually run.
- Before publishing, test both Server and Client Output and cover: Board 1 onboarding, Board 2 progression, resume/exit, all normal modes without timer UI or timeout, hint-based stars, hint purchases, retired-item migration, pending retired receipts, Daily rollover, OneLife loss, Duel, playtime rewards, admin reset, DataStore failures, respawn, and shutdown saving.
- Clearly distinguish source validation from Roblox Studio and published-place validation.

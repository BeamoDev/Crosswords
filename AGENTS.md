# Word Search repository instructions

These instructions apply to the entire repository.

## Published-version reconciliation gate (2026-09-04)

- The user has reverted the Roblox Studio place to the currently published version, but that exact Studio source and its authored instances have not yet been synchronized into this checkout.
- Do not treat the current worktree, `README.md`, or `src/REVAMP_HANDOFF.md` as proof of what is live. The worktree still contains a large, unfinished 1,000-level modular-UI redesign layered over the tracked unpublished revamp.
- Git commit `a66ebf8` (`checkpoint: pre-revamp source`) is the strongest repository candidate for the published code, but it remains a comparison snapshot until checked against the restored Studio hierarchy and scripts.
- Before changing gameplay, UI, persistence, remotes, monetization, or content, first export or synchronize the restored Studio source, inspect the exact hierarchy/casing, and update this file plus the README/handoff to match it.
- Do not reset, check out, delete, publish, or copy either the dirty redesign worktree or `a66ebf8` into Studio without the user's explicit choice. Preserve both for reconciliation.
- Runtime Studio hierarchy and fresh Server/Client Output override all repository assumptions. Clearly distinguish source inspection from Studio and published-place validation.

The revamp-specific rules below are conditional guidance for the local revamp source. They do not currently describe the confirmed published game.

## Start here

- Read `README.md` and `src/REVAMP_HANDOFF.md` before modifying gameplay, persistence, remotes, UI structure, or level content.
- Once the reconciliation gate above is cleared, treat the selected synchronized source as authoritative rather than an older handoff or redesign draft.
- Preserve unrelated working-tree changes and keep separate private backups of the Roblox place. This repository does not contain every Studio-authored asset.

## Runtime boundary and mapping

- This checkout has no Rojo project. Do not add Rojo, Wally, Rokit, or generated place configuration unless the workflow is intentionally changed.
- Map `src/client` to `StarterPlayerScripts.client`, `src/server` to `ServerScriptService.server`, and `src/shared` to lowercase `ReplicatedStorage.shared`.
- Keep exactly one active `GameController` LocalScript and one `ServerBootstrap` Script.
- The server creates `ReplicatedStorage.WordSearchRevampRemotes`; clients must not create fallback or shadow remotes.
- The client creates `WordSearchUI` at runtime. Do not enable an old authored HUD or the retired `WordSearchRevampHUD` alongside it.

## Current architecture

- `src/client/GameController.local.luau`
  Client entrypoint. Loads shared configuration, binds remotes, owns view state, and coordinates the scripted UI, input, audio, animation, and environment controllers.
- `src/client/ui/AppController.luau`
  Composes the complete `WordSearchUI`, registers screens and modal flows, applies accessibility/cosmetic presentation, and preserves the public UI contract consumed by `GameController` and `InputController`.
- `src/client/ui/Screens/`
  Purpose-built modules for loading, home, Classic/chapter/level selection, Daily, gameplay, tutorial, achievements, shop, settings, pause, confirmation, victory, and errors.
- `src/client/ui/Components/`
  Reusable top bar, navigation drawer, puzzle board, word list, action toolbar, mode/chapter/level cards, progress, star, modal, and tooltip components.
- `src/client/ui/Theme.luau`, `Assets.luau`, `ResponsiveController.luau`, `ScreenRouter.luau`, and `ModalController.luau`
  Central visual tokens and real image-asset slots, safe-area layouts, page focus, and single-modal routing.
- `src/client/revamp/InputController.luau`
  Handles mouse, touch, keyboard, and gamepad selection. Pointer work is sampled only during an active gesture.
- `src/client/revamp/AnimationController.luau`
  Cancellable UI tweens and reduced-motion behavior.
- `src/client/revamp/AudioController.luau`
  Configured sound assets and fallback sounds under `SoundService`.
- `src/client/revamp/EnvironmentController.luau`
  Client-only camera and atmosphere treatment with teardown restoration.
- `src/server/bootstrap/ServerBootstrap.server.luau`
  Server entrypoint. Creates remotes, validates requests, applies rate limits, loads profiles, wires round/economy endpoints, and starts Studio tests.
- `src/server/content/LevelCatalog.luau`
  Server-only six-chapter, 1,000-level catalog. It owns authored definitions, themed word banks, and deterministic expansion rules.
- `src/server/puzzle/PuzzleGenerator.luau` and `PuzzleValidator.luau`
  Deterministic generation, path compilation, occurrence checks, and definition validation.
- `src/server/services/gameplay/PuzzleService.luau`
  Resolves Classic, Quick, Daily, and Zen requests and returns sanitized public puzzles.
- `src/server/services/gameplay/RoundService.luau`
  Owns active rounds, canonical paths, selection checks, hints, pause state, completion, and per-round action serialization.
- `src/server/services/gameplay/RewardService.luau`
  Calculates ranked eligibility, stars, XP, coins, achievements, and daily completion rewards before applying them through `DataService`.
- `src/server/data/DataService.luau`
  Sole persistent profile owner. Handles normalization, leased sessions, idempotent receipts, autosave, release, and snapshots.
- `src/server/data/EconomyProfile.luau`
  Pure profile mutations performed while `DataService` owns the profile lock.
- `src/server/services/meta/DailyPuzzleService.luau`
  Stable UTC daily identity, reset timing, and streak rules.
- `src/server/services/meta/EconomyService.luau`
  Server-side catalog resolution, daily-login claims, coin purchases, and cosmetic equips.
- `src/server/services/ops/RateLimiter.luau` and `src/server/utils/RemoteValidator.luau`
  Per-player endpoint throttles and bounded remote payload schemas.
- `src/server/tests/PuzzleEngineTests.luau`
  Static content and engine coverage, including all 1,000 levels and deterministic fixtures.
- `src/shared/config/GameConfig.luau`
  Schema/content/generator revisions, datastore name, gameplay bounds, progression, modes, achievements, and asset placeholders.
- `src/shared/config/RemoteConfig.luau` and `ShopConfig.luau`
  Remote names and the server-readable coin/cosmetic catalog.

## Authority and security invariants

- Keep canonical puzzle targets and paths server-only. Never send them to a client before an authorized hint or terminal result requires a sanitized reveal.
- The server owns round IDs, seeds, timers, pause state, found targets, completion, stars, XP, coins, hints, achievements, unlocks, and economy mutations.
- A client submits only bounded intent such as a mode/level request or two selection endpoints. Continue validating payload shape with `RemoteValidator`, throttling with `RateLimiter`, and matching against `RoundService` state.
- Keep round-wide action serialization so selection, hint, pause, and completion writes cannot overlap.
- Preserve idempotent completion and shop receipts, including the ambiguous-`UpdateAsync` retry path.
- Keep implausibly fast or excessive clears unranked. Do not grant progression when `RewardService` rejects ranked eligibility.
- Disabled Developer Product placeholders are not a receipt implementation. Do not enable Robux products until real IDs and idempotent `ProcessReceipt` handling exist.
- Never commit credentials, tokens, webhook URLs, local place files, or production data exports.

## Persistence rules

- The current production store is `WordSearchRevamp_v1`, schema version 1, keyed with `player_<UserId>`.
- Studio profiles are deliberately memory-only. Do not make Studio read or overwrite production data as a convenience.
- `DataService` is the only module that may own persistence, profile normalization, session leases, dirty state, save retries, and snapshots.
- Keep player mirrors synchronized through `DataService`; do not mutate snapshot tables on the client and treat them as saved state.
- Preserve leased-session ownership, mutation locking, capped retries, release-request behavior, 60-second autosave, `PlayerRemoving`, and the bounded `BindToClose` budget.
- When changing saved data, update defaults, normalization, snapshot construction, mirrors, limits, and tests together. Change `SchemaVersion` only with an intentional migration plan.
- Do not read, overwrite, or delete an older datastore without explicit migration requirements and published-environment validation.

## Gameplay and content rules

- Current modes are Classic, Quick, Daily, and Zen. Zen is server-supported but intentionally hidden from the main menu; Time Attack is not implemented.
- Classic has 1,000 levels in six chapters. Unlock order and best stars/times are durable progression.
- Every normal play generates a fresh server-owned seed. A seed remains deterministic for debugging, but replay must not reuse a completion identity.
- Daily word-list identity is pinned by `GameConfig.DailyRotation`, independent of `ContentRevision`. Schedule rotation changes just after UTC rollover so mixed live servers cannot split the day's challenge.
- Keep `GameConfig.ContentRevision`, `GeneratorVersion`, catalog definitions, daily rotation, and pinned test hashes consistent. Revision changes deliberately invalidate incompatible in-flight rounds.
- For new levels, use stable lowercase IDs, valid chapter/order metadata, bounded grids/words, and a supported difficulty. Authored targets must match their words and may not duplicate the same physical path in reverse.
- Update puzzle generation and server validation together. Never implement a generation rule only in the client.
- The shop spends saved coins, and its daily-login claim and cosmetic equip actions are wired into dedicated client screens. Keep those mutations server-authoritative.

## Client and accessibility rules

- Review mouse, touch, keyboard, and gamepad paths together for any input or focus change.
- Preserve arithmetic board hit-testing, active-gesture-only pointer sampling, cached cell geometry, and centralized input enable/disable behavior.
- Keep selection previews presentation-only; the client must not infer or award a valid word.
- Use `GuiButton.Activated` for mouse, touch, and controller parity, and preserve visible gamepad focus.
- Maintain phone portrait/landscape, tablet, desktop, ultrawide, and console safe-area layouts with readable cells and at least 48-pixel primary controls where practical.
- Honor reduced motion, high contrast, colorblind mode, music/SFX toggles, and volume settings. Environment teardown must restore the prior camera and lighting state it owns.
- Asset IDs in `GameConfig.Assets` may remain empty. Missing optional art/audio should degrade safely and warn at most once.

## Validation and release claims

- Run `require(game.ServerScriptService.server.tests.PuzzleEngineTests).Run()` in Studio after content, generator, validator, economy, or remote-schema changes. The server bootstrap also runs it automatically in Studio.
- Inspect changes for merge markers, credentials, unexpected binary place files, malformed level data, and client/server contract drift.
- Use Studio Script Analysis and inspect both Server and Client Output.
- Before release, test with at least two clients: all input types, every visible mode, Daily rollover, hints, pause/replay/next, settings, tutorial, respawn/leave, rate limiting, DataStore denial, receipt replay, autosave, and shutdown.
- Clearly distinguish source/static validation from Roblox Studio and published-place validation. Source tests cannot prove Studio hierarchy, assets, streaming, DataStores, device layout, or live service behavior.

## Repository hygiene

- Keep repository files under `src/` plus `README.md`, `AGENTS.md`, `.gitignore`, `.gitattributes`, and intentional `.github/` files.
- Do not commit `.rbxl`, `.rbxlx`, lock files, logs, editor state, temporary files, environment files, keys, or certificates.
- Preserve LF endings for Lua/Luau/Markdown and CRLF for PowerShell through `.gitattributes`.

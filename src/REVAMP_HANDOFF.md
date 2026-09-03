# Word Search revamp handoff

This source tree is the local, unpublished implementation of the Word Search revamp. The pre-revamp source is preserved in Git commit `a66ebf8` (`checkpoint: pre-revamp source`).

## Runtime architecture

```text
client
├── GameController.local.luau
└── revamp
    ├── AnimationController.luau
    ├── AudioController.luau
    ├── InputController.luau
    ├── Theme.luau
    └── UIController.luau
server
├── bootstrap
│   └── ServerBootstrap.server.luau
├── content
│   └── LevelCatalog.luau
├── data
│   ├── DataService.luau
│   └── EconomyProfile.luau
├── puzzle
│   ├── PuzzleGenerator.luau
│   └── PuzzleValidator.luau
├── services
│   ├── gameplay
│   │   ├── PuzzleService.luau
│   │   ├── RewardService.luau
│   │   └── RoundService.luau
│   ├── meta
│   │   ├── DailyPuzzleService.luau
│   │   └── EconomyService.luau
│   └── ops
│       └── RateLimiter.luau
├── tests
│   └── PuzzleEngineTests.luau
└── utils
    └── RemoteValidator.luau
shared
├── config
│   ├── GameConfig.luau
│   ├── RemoteConfig.luau
│   └── ShopConfig.luau
└── types
    └── GameTypes.luau
```

The client builds the complete HUD at runtime, previews input, and renders server responses. `EnvironmentController` owns the client-only sky camera, lighting grade, bloom, atmosphere, and blur, and restores the original scene on teardown. Its camera movement uses long engine tweens rather than a per-frame Lua callback. The client never receives canonical target paths. The server selects or generates each puzzle, owns the canonical paths and timer, infers completion, calculates rewards, and writes progression.

Additional backend modules are `server/services/meta/EconomyService.luau`, `server/data/EconomyProfile.luau`, and `shared/config/ShopConfig.luau`.

Economy responsibilities are deliberately split: `EconomyService` resolves server-owned catalog entries, `EconomyProfile` applies pure mutations while the profile lock is held, and `DataService` alone owns normalization, persistence, retries, and snapshots.

The supported product flows are:

- Classic: a 120-level, six-chapter progression with locks, best times, and best stars. Definitions retain stable word lists and difficulty, while every play/replay receives a fresh server-generated grid.
- Quick: chooses an unlocked puzzle near the player's current progression and generates a fresh server seed.
- Daily: deterministic UTC word-list identity from a pinned rotation manifest, a fresh grid on every load, plus once-per-day hint/XP/coin rewards with streak tracking.
- Economy APIs: server-authoritative UTC login claims, coin purchases, and cosmetic ownership/equipping remain available to future client work; the restored original UI does not expose new Rewards or Shop screens.
- Zen: supported by the server contract as an untimed, explicitly unranked mode, but intentionally has no primary-menu button yet.

Time Attack was deliberately deferred so the three priority modes did not inherit a second, partially implemented round lifecycle.

## Remotes

All remotes live under `ReplicatedStorage.WordSearchRevampRemotes` and are created by the server bootstrap.

| Kind | Name | Accepted client data | Server checks |
| --- | --- | --- | --- |
| Function | `GetBootstrap` | none | rate limit, safe profile availability |
| Function | `StartRound` | `{mode, levelId?}` | mode allowlist, ID format, unlock state, puzzle validation |
| Function | `SubmitSelection` | `{roundId, startCell, endCell}` | GUID/coordinate schema, bounds, rate limit, active round, pause state, straight 8-way path, canonical server target |
| Function | `RequestHint` | `{roundId, requestId}` | active round, idempotent request receipt, cooldown, server hint balance, unfound target |
| Function | `SetPaused` | `{roundId, paused}` | active round, boolean schema, cooldown |
| Function | `UpdateSettings` | `{name, value}` | setting allowlist, boolean/0..1 type and range, rate limit |
| Function | `CompleteTutorial` | none | profile readiness and rate limit |
| Function | `ClaimDailyReward` | none | profile readiness, server UTC day, durable once-per-day gate |
| Function | `PurchaseShopItem` | `{productId, requestId}` | server catalog/price, balance, ownership, durable request receipt, rate limit |
| Function | `EquipCosmetic` | `{kind, itemId}` | category allowlist, saved ownership, rate limit |
| Event | `AbandonRound` | `{roundId}` | ID schema, rate limit, ownership |
| Event | `StateUpdated` | server to client only | sanitized profile snapshot |
| Event | `ServerNotice` | server to client only | presentation notices |

The client cannot submit a word, board, seed, elapsed time, stars, XP, hint reward, unlock, or completion flag. A submitted endpoint pair is expanded and matched against a server-only path lookup. Round-wide action serialization prevents overlapping selection/hint writes. Completion receipts make reward writes idempotent, including an ambiguous DataStore response retry. Implausibly fast solves and excessive completion velocity (checked both in memory and against durable receipts across server hops) finish visually but grant no progression and cause no completion write.

The board input hot path uses arithmetic grid hit-testing instead of scanning every cell. Grid letters are passive render objects, and one invisible board focus proxy replaces hundreds of controller-selectable targets and per-cell connections. Every board omits decorative per-cell strokes, corners, markers, and text constraints, reducing each letter from six instances to two while retaining its color state and the selection capsule's correct layer between the tile and letter. Grid and word-list layouts are detached during rebuilds so hundreds of child changes produce one final layout pass. Idle mouse movement does no Lua board work. During a drag, the pointer is sampled directly at no more than 60 Hz instead of subscribing to the mouse's potentially much faster raw `InputChanged` stream. Unchanged coordinates are ignored, and the current cell's cached screen rectangle turns most movement into four numeric comparisons; full arithmetic hit-testing runs only after the pointer leaves that cell. The endpoint changes only after entering a new snapped cell, and the full word path is built once on release. Drag previews reuse a two-endpoint buffer and update the original rounded capsule from cached grid geometry without recoloring letter boxes or forcing per-frame cell layout reads. Board scrolling is suspended only during the active gesture so it cannot fight the pointer. Keyboard and gamepad selection remain event-driven and do not start the pointer render loop. One shared focus observer handles the board and all real controls; ordinary buttons retain only their activation connection, with Lua hover/press tweens removed. Input enable/disable is centralized instead of rewriting properties across the whole grid. The client timer uses one 2 Hz task during gameplay instead of a 60 Hz Heartbeat callback and wakes only once per second elsewhere. Result feedback repaints only affected cells, and unchanged timer/progress values are not re-rendered. The level browser expands one chapter at a time and batches its grid layout so the 120-level catalog does not create or relayout every level button at once. `H` / gamepad X requests a hint, and `P` / gamepad Start pauses.

## Datastore

- Store name: `WordSearchRevamp_v1`
- Schema version: `1`
- Production persistence: leased sessions, protected `UpdateAsync` retries/backoff, dirty tracking, 60-second autosave, `PlayerRemoving`, and `BindToClose`.
- Release requests survive long in-flight writes and retry immediately after the profile mutation lock opens; release-requested sessions are excluded from autosave heartbeats. Departing playtime freezes at the first release request, and failed outer release/lease-cleanup retries are capped so an outage cannot create an unbounded retry storm; any remaining remote lease expires naturally.
- Studio persistence: memory-only. Studio play tests do not read or overwrite production data.
- Old stores are neither read nor deleted.
- Existing schema-v1 profiles are migrated in place by normalization: missing coin, reward, cosmetic-category, and expanded-setting fields receive bounded defaults and are saved normally. The datastore name and schema version did not change.

Profile shape:

```text
progression
  unlockedLevel, xp, tutorialCompleted
  levelProgress[levelId] = {stars, bestTimeMs, clears}
inventory
  hints, coins
stats
  totalPuzzlesCompleted, totalWordsFound, totalHintsUsed
  totalMistakes, perfectSolves, totalPlaySeconds, modeClears
daily
  lastCompletedDay, currentStreak, bestStreak, totalCompleted
settings
  music, sfx, musicVolume, sfxVolume, uiAnimations
  reducedMotion, highContrast, colorblindMode
rewards
  lastClaimDay, totalClaims
achievements
  achievementId = earned Unix timestamp
cosmetics
  owned/equipped themes, trails, backgrounds, UI styles
idempotency
  roundCompletions (bounded recent durable receipts)
  shopPurchases (bounded durable request receipts)
meta
  createdAt
```

The rank and total-star values sent to clients are derived from saved XP and level progress rather than separately persisted counters.

## Adding a level

Edit `server/content/LevelCatalog.luau` and add one entry to the ordered `levels` array. It is server-only so authored target paths and generation seeds never replicate to clients.

For generated levels, provide:

- stable lowercase `id`, chapter ID, chapter order, title, description;
- `Easy`, `Medium`, `Hard`, or `Expert` difficulty;
- width and height within `GameConfig.Gameplay` limits;
- time limit, deterministic integer seed, and uppercase unique words;
- words that fit at least one allowed direction for that difficulty.

For authored levels, also provide an uppercase row string for every grid row and one exact path per target. Targets must match the word order. No two targets may share the same physical path, even in reverse.

Run the validation suite after every content edit:

```luau
require(game.ServerScriptService.server.tests.PuzzleEngineTests).Run()
```

The server also runs this suite automatically in Studio and reports the pass count. The same module can be required by the standalone Luau CLI for fast local audits. Tests cover all 120 levels, deterministic fixture hashes, randomized runtime variants (including authored definitions), eight directions, malformed data, duplicate occurrences, reverse-path collisions, and palindromes. A seed still reproduces the same board for debugging, but gameplay requests receive a new server-owned seed on every load. If generator behavior intentionally changes, increment `GameConfig.GeneratorVersion`, update `ContentRevision`, and deliberately update the pinned fixture hashes. Daily rotation IDs and `DailyRotation.Revision` are intentionally separate; stage changes just after a UTC rollover so mixed live servers cannot split the day's word-list identity.

## Placeholder assets

Final asset slots are in `shared/config/GameConfig.luau`:

- `Assets.LogoImage`
- `Assets.ChapterImages`
- `Assets.Sounds.Button`
- `Assets.Sounds.Correct`
- `Assets.Sounds.Incorrect`
- `Assets.Sounds.Complete`
- `Assets.Sounds.Hint`
- `Assets.Sounds.Unlock`
- `Assets.Sounds.Music`

Image values may be numeric asset IDs or `rbxassetid://...` strings. Setting `LogoImage` replaces the scripted `W` tile on the loading screen; `ChapterImages` accepts chapter-ID keys (for example `Animals = 123456`) and renders subtle card artwork.

Sound values may be numeric IDs or `rbxassetid://...` strings. Until IDs are supplied, `AudioController` reuses matching `Sound` instances under `SoundService/SFX` and `SoundService/Music`. Missing slots warn once and remain silent. Fonts currently use Roblox-native Gotham variants defined in `Theme.luau`, so no font asset is required.

## Removed legacy source

The following unreferenced systems were removed after the new dependency graph was checked:

- Client: old camera, board runtime, classic-level wrapper, timed products, input bindings, authored-HUD bootstrap, auto-rejoin, old music player, and all old UI helper/duel/meta/summary modules.
- Server: old player datastore/session store, board validation, duel/progression/meta/leaderboard services, admin/analytics/anti-AFK/day-night/webhook services, webhook example config, and old utility modules.
- Shared: old board generator/definition builder, meta/economy configs, level/puzzle/theme/word libraries, daily/gift/star/timer progression modules, and old UI effects.
- Replaced in place: `client/GameController.local.luau`, `server/bootstrap/ServerBootstrap.server.luau`, and `shared/config/RemoteConfig.luau`.

Exact removal manifest:

```text
client/audio/MusicPlayer.luau
client/camera/CameraRuntime.luau
client/gameplay/BoardRuntime.luau
client/gameplay/ClassicLevels.luau
client/gameplay/TimedProductRuntime.luau
client/input/InputBindings.luau
client/system/AutoRejoin.luau
client/system/InterfaceBootstrap.luau
client/ui/ButtonUI.luau
client/ui/DuelUI.luau
client/ui/GroupIntro.luau
client/ui/GuiUtils.luau
client/ui/MetaUI.luau
client/ui/SummaryRuntime.luau
client/ui/UiBootstrapRuntime.luau
client/ui/ViewTransitions.luau
server/config/WebhookConfig.example.luau
server/data/PlayerDataStore.luau
server/services/gameplay/BoardValidationService.luau
server/services/gameplay/DuelService.luau
server/services/gameplay/ProgressionService.luau
server/services/meta/LeaderboardService.luau
server/services/meta/MetaService.luau
server/services/ops/AdminCommandService.luau
server/services/ops/AnalyticsService.luau
server/services/ops/AntiAfkService.luau
server/services/ops/DayNightCycleService.luau
server/services/ops/WebhookService.luau
server/session/PlayerSessionStore.luau
server/utils/InstanceUtils.lua
server/utils/SharedConfig.lua
server/utils/TableUtils.lua
server/utils/WordPathUtils.lua
shared/board/BoardGenerator.luau
shared/board/DefinitionBuilder.luau
shared/config/MetaConfig.luau
shared/config/PuzzleEconomy.luau
shared/content/Levels.luau
shared/content/PuzzleLibrary.lua
shared/content/ThemedModeLibrary.luau
shared/content/WordBank.luau
shared/progression/DailyMode.luau
shared/progression/GiftProgress.luau
shared/progression/StarRules.luau
shared/progression/TimerRules.luau
shared/ui/UIEffects.luau
```

Git retains the exact removed versions at the checkpoint above.

## Manual Studio checklist

1. Sync or copy this source tree into the same services/folders used by the existing project. Confirm there is exactly one active `GameController` LocalScript and one `ServerBootstrap` Script.
2. If the place contains a manually authored legacy HUD in `StarterGui`, disable or remove it after confirming `WordSearchRevampHUD` appears. The new HUD is fully scripted and uses display order 20.
3. Start a Studio server with at least two players. Confirm both reach Loading, Menu, Levels, Daily, and a playable board without infinite-yield warnings.
4. Run `PuzzleEngineTests.Run()` and require every test to pass. Confirm all 120 catalog levels generate.
5. On desktop, drag valid, invalid, duplicate, backward, vertical, diagonal, and overlapping words; release outside the board; rapidly submit; pause/resume; request hints; respawn and leave mid-round.
6. In Device Emulator, check narrow phone portrait/landscape, tablet, 16:9 desktop, ultrawide, and console safe areas. Verify 48 px minimum controls, readable cells, no overlap, and usable touch dragging. On an Expert board, also tap a starting letter, pan the oversized board, and tap the ending letter to verify the long-word touch fallback.
7. With a gamepad, navigate every screen and collapsed chapter, select a start/end cell, cancel a selection, use X for a hint and Start to pause, open/close modals, and verify visible focus strokes.
8. Toggle music, SFX, reduced motion, and high contrast. Confirm reduced motion stops the sky pan and high contrast makes glass surfaces opaque. Rejoin in a published test universe to verify production persistence; Studio intentionally resets its memory profile when the server stops.
9. Complete Classic levels with different times/mistakes/hints. Confirm stars only improve, best time decreases, the next level unlocks, pausing caps the result at two stars, and Replay cannot duplicate the same round receipt.
10. Complete Daily twice, around UTC reset if practical. Confirm its daily reward grants once, streak changes once, and reset identity is shared between players.
11. Exercise the economy remotes from a controlled test client or server harness; confirm duplicate daily claims and purchase request IDs are idempotent and invalid equips are rejected.
12. Simulate DataStore denial/timeout and a malformed puzzle. Confirm the explicit retry UI appears, no disposable production profile is created, and no reward is double-granted after retry.
13. Inspect server output and the DataStore budget. Confirm remotes rate-limit spam, instant/burst clears are visibly marked unranked without granting progression, player removal clears round/bucket state, autosave remains near one write per minute, and shutdown completes within its configured budget.

## Known limitations and manual decisions

- Standalone Luau compile checks and `PuzzleEngineTests` pass locally; Roblox Studio device, camera, controller, and DataStore testing is still required before publishing.
- The work is local and has not been published or written into a live place.
- Time Attack is not implemented. Zen is server-ready but not exposed on the primary menu.
- Logo/chapter artwork and explicit sound IDs remain placeholders.
- Robux coin-pack definitions remain disabled because no real Developer Product IDs were supplied.
- The UI now uses a vibrant blue glass palette over a blurred, color-graded sky camera. Backend economy work remains but has no new client-facing screen.

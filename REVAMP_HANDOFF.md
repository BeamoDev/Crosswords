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
│   └── DataService.luau
├── puzzle
│   ├── PuzzleGenerator.luau
│   └── PuzzleValidator.luau
├── services
│   ├── gameplay
│   │   ├── PuzzleService.luau
│   │   ├── RewardService.luau
│   │   └── RoundService.luau
│   ├── meta
│   │   └── DailyPuzzleService.luau
│   └── ops
│       └── RateLimiter.luau
├── tests
│   └── PuzzleEngineTests.luau
└── utils
    └── RemoteValidator.luau
shared
├── config
│   ├── GameConfig.luau
│   └── RemoteConfig.luau
└── types
    └── GameTypes.luau
```

The client builds the complete HUD at runtime, previews input, and renders server responses. It never receives canonical target paths. The server selects or generates each puzzle, owns the canonical paths and timer, infers completion, calculates rewards, and writes progression.

The supported product flows are:

- Classic: a 24-level, six-chapter progression with locks, best times, and best stars.
- Quick: chooses an unlocked puzzle near the player's current progression and generates a fresh server seed.
- Daily: deterministic UTC puzzle identity from a pinned rotation manifest, plus a once-per-day hint/XP reward with streak tracking.
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
| Function | `UpdateSettings` | `{name, value}` | setting allowlist, boolean value, rate limit |
| Function | `CompleteTutorial` | none | profile readiness and rate limit |
| Event | `AbandonRound` | `{roundId}` | ID schema, rate limit, ownership |
| Event | `StateUpdated` | server to client only | sanitized profile snapshot |
| Event | `ServerNotice` | server to client only | presentation notices |

The client cannot submit a word, board, seed, elapsed time, stars, XP, hint reward, unlock, or completion flag. A submitted endpoint pair is expanded and matched against a server-only path lookup. Round-wide action serialization prevents overlapping selection/hint writes. Completion receipts make reward writes idempotent, including an ambiguous DataStore response retry. Implausibly fast solves and excessive completion velocity (checked both in memory and against durable receipts across server hops) finish visually but grant no progression and cause no completion write.

## Datastore

- Store name: `WordSearchRevamp_v1`
- Schema version: `1`
- Production persistence: leased sessions, protected `UpdateAsync` retries/backoff, dirty tracking, 60-second autosave, `PlayerRemoving`, and `BindToClose`.
- Release requests survive long in-flight writes and retry immediately after the profile mutation lock opens; release-requested sessions are excluded from autosave heartbeats. Departing playtime freezes at the first release request, and failed outer release/lease-cleanup retries are capped so an outage cannot create an unbounded retry storm; any remaining remote lease expires naturally.
- Studio persistence: memory-only. Studio play tests do not read or overwrite production data.
- Old stores are neither read nor deleted.

Profile shape:

```text
progression
  unlockedLevel, xp, tutorialCompleted
  levelProgress[levelId] = {stars, bestTimeMs, clears}
inventory
  hints
stats
  totalPuzzlesCompleted, totalWordsFound, totalHintsUsed
  totalMistakes, perfectSolves, totalPlaySeconds, modeClears
daily
  lastCompletedDay, currentStreak, bestStreak, totalCompleted
settings
  music, sfx, reducedMotion, highContrast
achievements
  achievementId = earned Unix timestamp
cosmetics
  ownedThemes, equippedTheme
idempotency
  roundCompletions (bounded recent durable receipts)
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

The server also runs this suite automatically in Studio and reports the pass count. Tests cover the whole catalog, deterministic fixture hashes, eight directions, malformed data, duplicate occurrences, reverse-path collisions, and palindromes. If generator behavior intentionally changes, increment `GameConfig.GeneratorVersion`, update `ContentRevision`, and deliberately update the pinned fixture hashes. Daily rotation IDs and `DailyRotation.Revision` are intentionally separate; stage changes just after a UTC rollover so mixed live servers cannot split the day's identity.

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
4. Run `PuzzleEngineTests.Run()` and require every test to pass. Confirm all 24 catalog levels generate.
5. On desktop, drag valid, invalid, duplicate, backward, vertical, diagonal, and overlapping words; release outside the board; rapidly submit; pause/resume; request hints; respawn and leave mid-round.
6. In Device Emulator, check narrow phone portrait/landscape, tablet, 16:9 desktop, ultrawide, and console safe areas. Verify 48 px minimum controls, readable cells, no overlap, and usable touch dragging. On an Expert board, also tap a starting letter, pan the oversized board, and tap the ending letter to verify the long-word touch fallback.
7. With a gamepad, navigate every screen, select a start/end cell, cancel a selection, open/close modals, and verify visible focus strokes.
8. Toggle music, SFX, reduced motion, and high contrast. Rejoin in a published test universe to verify production persistence; Studio intentionally resets its memory profile when the server stops.
9. Complete Classic levels with different times/mistakes/hints. Confirm stars only improve, best time decreases, the next level unlocks, pausing caps the result at two stars, and Replay cannot duplicate the same round receipt.
10. Complete Daily twice, around UTC reset if practical. Confirm its daily reward grants once, streak changes once, and reset identity is shared between players.
11. Simulate DataStore denial/timeout and a malformed puzzle. Confirm the explicit retry UI appears, no disposable production profile is created, and no reward is double-granted after retry.
12. Inspect server output and the DataStore budget. Confirm remotes rate-limit spam, instant/burst clears are visibly marked unranked without granting progression, player removal clears round/bucket state, autosave remains near one write per minute, and shutdown completes within its configured budget.

## Known limitations and manual decisions

- This environment had no Rojo project file or Luau CLI, so source-level dependency, whitespace, deterministic simulation, and adversarial code reviews were performed here; the Studio checklist above is still required before publishing.
- The work is local and has not been published or written into a live place.
- Time Attack is not implemented. Zen is server-ready but not exposed on the primary menu.
- Logo/chapter artwork and explicit sound IDs remain placeholders.
- Cosmetic theme ownership is schema-ready, but only the default visual theme is selectable in this release.

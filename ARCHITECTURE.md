# Crosswords architecture

Current source contract, 2026-09-25. [README.md](README.md) describes controls and mode sizes; [PLAYER_DATA.md](PLAYER_DATA.md) describes persistence. This is the crossword conversion of the shared-queue WordPath/Strands implementation, not the older crossword campaign.

## Ownership

| Path | Responsibility |
| --- | --- |
| `src/client/ClientBootstrap.local.luau` | Only client executable; mounts authored Main/GroupIntro, characterless startup, calls GameController |
| `client/controllers/GameController.luau` | Profiles, queues/rounds, transitions, locks, outcomes, timer, Duel and tutorial integration |
| `client/controllers/BoardController.luau` | Crossword cells, clues, virtual keyboard, entry feedback, server progress, finder portraits, score and Duel HUD |
| `client/controllers/InterfaceController.luau` | Authored hierarchy binding, queue cards/countdown, XP bars, home previews and motion |
| `client/controllers/ProgressionController.luau` | Retained reward/settings/leaderboard and modal UI |
| `client/features/` | Duels, Social, Tutorial and TutorialView |
| `client/systems/Input.luau` | Physical keyboard/gamepad navigation; pointer/touch buttons use Activated |
| `client/systems/` | Retained Audio, Device and Camera |
| `server/ServerBootstrap.server.luau` | Only server executable; remotes/services, characterless lifecycle, receipts, shutdown |
| `server/puzzle/PuzzleGenerator.luau` | Mode definitions, beginner policy, fixed practice and canonical puzzle assembly |
| `server/puzzle/CrosswordLayout.luau` | Bounded seeded interlocking Across/Down placement and numbering, adapted from original crossword |
| `server/content/CrosswordBank.luau` | 986 unique answer/clue records with original source ID/difficulty; never replicated |
| `server/services/QueueState.luau` | Pure queue, canonical per-member round state, typed validation, hints, score and private projections |
| `server/services/QueueService.luau` | Queue/solo admission, lifecycle, timeouts, XP/rewards, recipient-specific publication |
| `server/services/QueueBots.luau` | Verified-avatar companions, population/admission and adaptive canonical solves |
| `server/services/DuelService.luau`, `DuelBots.luau` | Invitations, races, independent progress, bot pool, outcomes and rematches |
| `server/services/TutorialService.luau` | Private practice, free reveal, no real rewards, persisted skip/completion |
| `server/services/RewardService.luau`, `SocialService.luau`, `FavouriteService.luau` | Purchases/settings/daily/group rewards; leaderboards; once-only favourite prompt |
| `server/data/` | DataService is sole persistence owner; DataSchema defaults/normalization/migration |
| `server/systems/` | Operations (camera/sky/private webhook/idle rejoin), Analytics |
| `shared/puzzle/PuzzleEngine.luau` | Answer checking and whitelist-only public/revealed projections |
| `shared/puzzle/PuzzleValidator.luau`, `PuzzleTypes.luau` | Entry ID/definition contracts and types |
| `shared/puzzle/CrosswordInput.luau` | Pure local shared-cell drafts, selected entry/cursor, editing and server-revealed locks |
| `shared/config/` | ProgressionConfig for score/XP/unlocks; GameConfig for timers/economy/meta configuration |
| `shared/network/NetworkContract.luau` | Existing remote names, request limits and telemetry allowlist |
| `shared/ui/UIEffects.luau` | Retained effects API, also required by authored Main.FX |
| `shared/utility/Utility.luau` | Retained utilities |

All source paths in the table are under `src/`. Server `puzzle` and `content` folders are siblings of `services`, not children of shared. The old shared theme generator, theme banks, English bonus dictionary/shards and shared test module are removed. Lune-only support is under `tests/`. Original OLDSRC is archived locally outside runtime source and excluded from Git.

## Generation

Definitions select maximum square size and exact clue count (see README). Beginner Standard and Mini filter to Easy bank entries. Other modes use the mixed bank. Layout shuffles deterministically, attempts at most 24 arrangements, crosses matching letters at right angles, prevents same-direction overlap, prevents letters touching entry endpoints and prevents parallel side adjacency. Every added entry crosses the existing component and adds at least one square. It scores candidates for compactness and crossings. Generation fails explicitly if a valid requested count cannot be produced; service admission cleanup preserves retryability.

Crop the result to its occupied bounds. Number starts in row-major order; Across and Down sharing a start share a number. Public IDs append A/D. All entries are forward-reading and at least three letters. Each multi-letter contiguous horizontal/vertical run corresponds to one clue. Sparse grids legitimately contain blocked squares and may be rectangular; there is no symmetry requirement and no filler-letter or exact-cover requirement.

Canonical `letters` contains answer letters and empty strings for blocks. Each `placedWordsByWord[id]` contains `id`, `number`, `direction`, `clue`, `length`, `path` and private `answer`. Historical field `words` is an ordered array of entry IDs. Never interpret the ID length as answer length or XP.

PublicPuzzle constructs a new whitelist-only object: the same dimensions, IDs, clues and paths, but `letters` contains only empty strings (blocks) or single spaces (open cells), and no `answer` or `seed`. Do not serialize canonical puzzle tables directly.

## Input and presentation

BoardController builds only gameplay content inside the authored board panel. It preserves panel Position/Size/AnchorPoint. The current clue occupies the top strip, a centered grid fits above an always-available QWERTY keyboard, and four buttons provide Prev/Erase/Next/Check. Cell sizes preserve square proportions within the authored square frame. Blank dark cells are passive; white letter cells are numbered TextButtons with Ubuntu Bold text.

Clue rows clone WordPanelTemplate, wrap the definition/length, and are ordered Across then Down, by number. Rows have a transparent Activated hit target, a readable clue region and retain BreakLine/FoundPanel. Confirmed rows remain in stable clue order without strike-through. Selected cells are pale blue, the cursor gold, and confirmed entries receive stable palette colours. Shared squares use a deterministic solved-entry colour. Hinted answers fill and lock their cells; they still require Check.

CrosswordInput owns per-cell drafts so intersections never have two conflicting visible letters. Selecting a crossing again switches direction. Typing advances along an entry, skipping authoritative locked cells. Incomplete entries never submit. Server progress replaces the lock map, fills only the local player's revealed entries and preserves unrelated drafts. Rebuild resets all editing state. Completion, time expiry, hidden Game, modals, transitions and pending requests block interaction.

Physical letters, arrows, Backspace, Enter, Space and Tab are handled centrally; native focus is never assigned or cleared. Pointer/touch and gamepad button actions use Activated. Gamepad supports native GUI navigation, the virtual keyboard, shoulder clue changes, X direction switching and B pause. Drafts survive pause. A Type answer TextBox opens the native device keyboard only when the user taps it. It edits the full entry while preserving crossing locks; Enter submits. No code captures or clears its focus.

Finder portraits use the existing verified image/palette system. Keep the first three chronological solvers per clue and authored Exceeds +N. Opponent confirmation changes only their portrait, never the local letters or local completion. Solo/practice omit portraits. Existing entrance/score/row effects cancel on rebuild and teardown.

## Authored UI contract

```text
StarterGui.Main / PlayerGui.Main (one ScreenGui on every device)
  Home
    GameIcon, Pattern, SelectModeLabel
    ButtonBar: Daily, Duel, Leaderboard, Settings
    Gamemodes: Standard.Play, Standard.Waiting.Frame.UIStroke
               Mini.Play, Jumbo.Play, Hardcore.Play
    LevelBar: Star, XP, FillBar.Fill
  Queue: Container.UIGridLayout, Subtitle, Exit, optional Solo, Pattern
  Game
    BOARDINFO.UIAspectRatioConstraint     BoardInfo / BoardPanel aliases accepted
      PuzzleGrid                         generated cells and blocks
      CurrentClue, CrosswordKeyboard     generated gameplay controls
    WordPanel.Words
    WordPanel.Container.ScrollingFrame.UIListLayout
      Clue_<id>                          WordPanelTemplate clones
    Hint.Owned.TextLabel
    OneVsOneMode                         player/opponent mugshots, names, counts and win rates
    TimedMode.TimeLeft, Icon              visible in every mode
    Score.Score, Score.Level.Label       optional; lowercase label alias accepted
    LevelBar.Star, XP, FillBar.Fill
    Background, Streak                   preserve authored content
    Title, Subtitle, Exit                optional legacy children
  Tutorial: Content.Title, Content.Paragraph, Skip, Icon, PopScale
  Frames: retained authored modals
ReplicatedStorage.Assets
  PlayerTemplate                         queue cards
  WordPanelTemplate: Word, BreakLine, PlayerTemplate, FoundPanel.UIListLayout
  Exceeds.TextLabel                      finder overflow
  LeaderboardTemplate                    ranking rows
  1v1Template                            Duel roster (legacy assets casing supported)
PlayerGui.GroupIntro                     retained startup sequence
```

Keep Main.FX requiring lowercase `ReplicatedStorage.shared.ui.UIEffects`. No device HUD clones, generated replacement menus or Studio assets. Missing optional Shop and Game headings must remain harmless. At zero hints the existing product prompt handles purchasing; no new Shop launcher is generated.

Home Standard/Mini previews now sweep straight Across/Down rows/columns, retaining timings/colours and cancellation. Jumbo retains its calm authored 3x3/6x6 decorative morph, independent of gameplay dimensions. Home icon, Pattern loops, waiting stroke, queue cards, white transitions, modal backdrop/scale, XP bars and leaderboard presentation retain their owners. Input stays locked through entry/exit and delayed packets cannot reopen an old view.

## Network and server authority

Keep existing remote folder names: `WordSearchBackendRemotes` and retained `Remotes.Events`/`Functions`/Duel. The name is compatibility plumbing, not gameplay branding.

QueueAction/TutorialAction Word payload: `{action="Word", roundId=<current id>, word=<entry id>, answer=<A-Z text>}`. Duel ReportDuelProgress: `{matchId=<current match>, word=<entry id>, answer=<A-Z text>}`. IDs and text are bounded; only ASCII letters, correct length and exact case-normalized spelling validate. Paths, client XP, score or found-word claims have no authority. Duel attempts, including incorrect guesses, are throttled. All services check membership, activity and deadline before awarding anything.

Round snapshots preserve `foundWords`, `hintedWords`, counts and `foundOrder` keyed by entry ID. `Snapshot(includePuzzle, recipientId)` includes `revealedAnswers` only on that recipient's member record. Shared broadcasts build a projection per recipient. It includes only their confirmed or hinted answers, never an opponent's. Duel sends the equivalent `myRevealedAnswers`; its hint boardState includes `revealedAnswers`. Opponent progress is IDs/counts only.

The first queue member starts one 15-second deadline, later joins do not extend it, empty queues cancel, and drained cohorts stay isolated from new arrivals. Below ten saved solves, each beginner has a private companion queue; graduates share public waiting. Queue revisions span both streams. ProfileReady/RoundBusy/DuelBusy/TutorialBusy gates prevent overlapping activities. Queue.Solo preserves waiting membership on generation failure.

Bots use canonical server answers through the same accepted-answer state transition, never Player profiles, inventories, XP, leaderboards or DataStores. Preserve global/private capacities, verified portrait filtering, staggered admission, adaptive human pacing, challenger limits, release ownership and shutdown cleanup. Duel has its separate eight-seat roster/population policy and rematch reservations.

Timers remain server deadlines: 180 seconds normally, Mini 90, Jumbo 300; Duel starts after countdown. Partial expiry preserves earned XP and grants no completion bonus. Hardcore fails only for an explicit known entry with a full-length incorrect alphabetic answer. Duplicates, incomplete/malformed payloads and inactive rounds do not create another outcome. Completed results freeze.

Every accepted human entry grants 20 XP per answer letter and increments lifetime Words Found once. Final completion grants 120 XP and the existing mode reward. Round score is 100 points/letter, or 50 for an answer explicitly hinted, plus floor(1000 * remaining/timeLimit) on completion only. Crossing letters count in each entry. Crown level is 1 + floor(score/500), bronze/silver/gold/diamond at levels 1/6/11/16. No profile score field is added.

## Tutorial and retained systems

Practice is the connected 3x3 CAT Across / CAR Down / RED Across crossword, with two blocked squares. Steps: Loading -> FirstAcross -> TryHint -> FirstDown -> LastAcross -> Win -> HomeCongrats. Select entries directly, teach typing and Check, reveal CAR through a free Hint, then solve RED using the crossing. The obsolete drag demonstration is removed. The entire board panel is the interaction opening so touch keys remain available. Retry/Skip, delayed-callback guards, normal animated Home return and durable onboarding state are retained. Practice awards no real XP, currency, Words Found or inventory changes.

DataService alone owns profile/session persistence, compact schema 19, serialized saves, ownership protection, pending-release retries and mirrors. Existing WordHuntQueueData_v1 and leaderboard namespaces are preserved; no production migration/reset. Rewards retain receipt idempotency and save-before-PurchaseGranted. Daily/group/level hint rewards, settings, favourite prompt, purchases, leaderboard caches and Duel records remain unchanged.

ServerBootstrap disables automatic characters. ClientBootstrap copies authored Main/GroupIntro only when absent, without relying on character spawn. Camera stays at the replicated CamPart pose, FOV 40; world sky uses the existing daytime transitions. Music/SFX settings and existing tracks remain. Private webhook URLs remain outside source.

## Verification boundary

The Lune suite covers generation, editing, public projection/privacy, malformed/stale requests, scoring/hints, queues/bots, timeouts, Duel/rematches, tutorial, profiles/rewards and mocked UI. Compile traverses runtime and tests. See README for commands. Studio must still validate actual hierarchy, responsive typography, keyboard/cell target sizes, tutorial overlap, controller focus navigation, multi-client behavior and paid receipts. Git publication does not publish a Roblox experience.

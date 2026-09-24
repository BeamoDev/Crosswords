# Strands source architecture

## Strands gameplay (2026-09-24)

Home.Gamemodes.Jumbo.CanvasGroup.Frame1 smoothly morphs directly between 3x3 and 6x6 over 1.6 seconds using Sine/InOut easing. Existing tiles tween position and size; new tiles scale up in their destinations and departing tiles shrink in place, without bouncing. UIGridLayout owns each resting layout and is temporarily parented to a generated JumboLayoutParking Folder during motion so changing columns cannot snap tiles into new rows; it is reattached after settling or cancellation. Layout positions preserve horizontal/vertical alignment and scaled/offset spacing. Missing Tile10-Tile36 clone the original tile art. The 3x3 layout uses authored CellSize/CellPadding; 6x6 keeps the same footprint (0.1475 cells and 0.015 spacing for the authored 0.3/0.03 values). Keep the calm cadence: initial 12-second pause, six seconds at 6x6, and 12-18 seconds at 3x3. Hidden Home, modals and transitions cancel motion and restore 3x3. Rebinding restores authored tile position/size/anchor/visibility/order and layout properties, removes generated tiles/scales/parking and preserves authored UIScales. No delayed callbacks can restart a destroyed preview. Jumbo gameplay remains 8x8.

Home.Gamemodes.Standard.CanvasGroup.Frame1 owns tile1 through tile25 in row-major 5x5 order; Mini has tile1 through tile9 in row-major 3x3 order. Capitalized Tile names and bare numeric names are also accepted. UIEffects.CreateHomeTilePreview traces random unique adjacent paths (diagonals allowed): Standard uses five or six tiles, Mini exactly three. Tiles highlight every 0.22 seconds with 0.4-second Sine easing, briefly hold, then fade to white over one second and immediately repeat, with no idle pause between cycles. Standard starts immediately and Mini after 0.25 seconds. Standard uses RGB (88,224,255), Mini (119,222,176). Only background/image colours change; letters, borders, layout and button interaction stay authored. The existing HUD Heartbeat runs previews while Home is enabled/visible, outside transitions and modals; hiding, rebinding or destroying cancels tweens and clears stale highlights. Returning Home promptly resumes both loops. Missing/incomplete optional grids do not block startup; these effects change no gameplay state.

Game.Score.Score shows `Score: X`; Game.Score.Level.Label (lowercase `label` also accepted) shows a crown emoji followed by `Level N`. Score resets to zero and Level 1 on every board, including practice and Duel/rematches. `ProgressionConfig.Score` owns 100 points per confirmed answer letter, reduced to 50 when that answer was hinted, plus `floor(1000 * remainingSeconds / timeLimit)` once for finishing all answers. The completion bonus is bounded from 0 to 1000 and freezes with the result; partial timeout, loss or forfeit has no completion bonus. Invalid/duplicate submissions, hints alone and extra dictionary words add no points. Server QueueState accumulates word score before clearing hint state; QueueService/TutorialService add the completion score only on the accepted final answer. Duel validates and accumulates independently, publishing `myScore` in progress and `score` in results; round member snapshots carry `score`. Clients display those authoritative values, never drag claims. Score level is `1 + floor(score / 500)`, without a hard cap. Crown text is bronze at levels 1-5, silver at 6-10, gold at 11-15 and diamond blue at 16+. Level gains gently pulse the authored label, and unchanged snapshots do not replay it. The Score frame remains authored and optional; no replacement is generated. Round score is session-only and separate from saved XP levels, hint rewards, mode unlocks, inventory and lifetime leaderboards. Duel victory still uses theme-word count, not this performance score.

The current authored Main.Game has no Exit, Title or Subtitle. Binding, board rendering and tutorial start/skip/finish tolerate their absence without creating replacements. Transitions animate the children that exist. Completed, timed-out and failed Hardcore rounds return through the existing result Play/Home controls; the existing manual pause Leave and Queue.Exit paths remain available. Game.Streak and Background retain their authored content.

The active game is now a Strands-style themed word puzzle, not a dictionary Word Hunt. Drag through adjacent letters, including diagonals; paths can bend. Backtracking removes the last tile, and a tile cannot repeat within a word. All target words, including the spangram, appear in the word panel from the start. Active drags use neutral grey highlights. Each confirmed word, including the spangram, receives its own vibrant color shared by its tiles, links, word row and success effects. Colors stay stable through updates and reset with a new board; the spangram still touches opposite edges. Every cell belongs to exactly one answer, and solved tiles can be used again for extra words without losing their permanent color. Completion requires all answers, including the spangram.

`PuzzleGenerator` is the mode/size facade; new `shared.puzzle.StrandsGenerator` owns seeded theme selection, exact letter-count matching, full-grid path generation and spangram placement. It draws from the existing 34 theme pools and five beginner pools. Snapshots add `rules = "Strands"`, `clue`, `theme` and `spangram`; no profile or remote names change. Canonical paths still serve hints and bots. `PuzzleEngine.MatchesStrand` validates forward or backward spelling, neighbouring unique cells and the canonical answer's tile set, so repeated-letter reorderings are accepted but another answer's tiles cannot be borrowed.

Every generated answer must be an existing uppercase A-Z entry in its authored theme word pool, including the spanning answer stored as spangram. Never turn a theme title or phrase into an answer by stripping spaces (such as YUMMYFOOD, LETSPLAY or FOODANDDRINK). The generator tries shuffled vocabulary words long enough to span the board and exact-covers the remaining cells with other unique vocabulary entries. Animals includes ELEPHANT/KANGAROO and Food includes SANDWICH/SPAGHETTI so Jumbo keeps those themes with familiar spanning words. The covering path includes diagonal bends, including its guaranteed fallback; every board still fills all cells and has a bending answer reaching opposite edges. Theme titles remain presentation text, not extra answers. This applies to newly generated boards; existing canonical round snapshots remain unchanged.

Dimensions are columns x rows: Standard 5x5 below ten solves and 7x7 afterward; Mini 5x5; Jumbo 8x8; Hardcore and Duel 7x7. Timed retains a 7x7 definition without a dedicated launcher. The private tutorial uses a fully covered 3x3 CAT/DOG/FOX practice grid inside the authored square frame, with bends, no spangram, and free hints. Standard/private queues, admission gates, bots, progression, receipts and the existing completion/replay flow remain active. Hardcore loses on an actual wrong 3+ letter adjacent selection; short, repeated-cell, skipped-cell and out-of-bounds payloads do not lose. Normal hints retain the existing inventory/shop system; non-theme words do not charge a free-hint meter.

Extra dictionary words of 3+ letters are recognized once per word per round in Standard, solo modes and Duel, but award no XP. Server validation reads the actual adjacent, unique-cell path in either direction; client word/XP claims are not authoritative. `EnglishDictionary` lazily loads twelve offline ENABLE2K word shards (173,432 entries); credits and source hash are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Accepted bonus words are session-only `member.bonusWords` / Duel `myBonusWords`; they do not claim tiles, add theme rows, advance completion/race scores, or count toward Words Found. They give a small tile pulse and sound, with no XP bar update or XP popup. Valid bonus words and repeats never fail Hardcore. A theme spelling found on alternate tiles awards no XP; its later canonical find awards the full normal theme XP. Tutorial practice and bots do not record extra words; completed/failed/exited rounds reject them. Bonus words reset for a new round; no profile schema or remote names change.

BoardController generates `PuzzleGrid`, white rounded tiles with faint black strokes and short colour-matched links between tile edges inside the authored square Main.Game.BOARDINFO frame (BoardInfo and legacy BoardPanel aliases accepted). No dark tray or bottom CurrentWord/DRAG TO CONNECT label is generated. The grid is centered and uses 98% of the frame, preserving authored position, size and background. It retains arithmetic pointer hit-testing, exact mouse/touch ownership, manual keyboard/controller navigation, input locks and cancellation. Fast pointer events sample intermediate cells; tile gaps are ignored so diagonal corner crossings do not select side neighbours. Tile faces occupy 76% of each cell. White faces and shadows reveal with the letter stagger. Tile highlights ease over 0.12 seconds, fresh links grow over 0.09 seconds, and confirmed words ripple through tile faces and pulse their list rows. Unchanged state does not restart effects; superseded tile tweens and destroyed links cancel cleanly. Logical input remains immediate. Tile letters use Ubuntu Bold. Solved letters stay white on their permanent solution colour; unsolved letters remain dark. Found connectors, including their inner cores, use the exact solution colour at full opacity. Selection connectors use grey, and hint links retain their white/gold pulse. The word counter shows only found/total (for example `0/6`), with no WORDS prefix or extra spaces. The word list has no generated instruction labels. Every target row stays visible before and after finds and hints; another player's find does not complete the local word. Found words are readable without strike-through. No UI focus is assigned. The authored Main, Home, Queue, modals and their transitions remain in use; no replacement screens or Studio assets are generated.

Local validation covers 2,076 generated boards, exact coverage, spanning, deterministic seeds, server rejection, drag/backtracking, visible target lists, hints and replay cleanup. These are source and mock checks; Studio visuals, phone layouts and live server behavior still require Studio verification. No Studio synchronization or publishing is part of this change.


## Active flow

ClientBootstrap -> GameController -> InterfaceController / BoardController / Input / retained modal features.
ServerBootstrap -> QueueService + DuelService + TutorialService -> DataService / RewardService / SocialService.
QueueService uses the pure QueueState transitions, QueueBots scheduler and the existing replicated PuzzleGenerator and PuzzleCatalog. DuelService uses DuelBots for its separate lobby pool and reuses QueueBots adaptive pacing.

There are 52 runtime source files (13 client, 14 server, 25 shared), the retained shared PuzzleTests.spec module, and local tests under tests/. The single client and server bootstraps remain the only executable Roblox scripts. The GameController StarterPlayerScripts descendant guard is retained.

Standard queues are local to one Roblox server. Joining twice never duplicates a member or restarts the timer. Removing the first player preserves the deadline while anyone remains. Empty queues cancel. At the deadline, the server detaches that cohort, publishes zero waiting, generates a single Standard definition/grid, and creates a round identified by a GUID. Later joins start another queue. Standard never turns into a competitive Duel simply because two people joined.

Standard is displayed as Standard Mode on Queue. QueueService calls BuildClassicDefinition with authoritative cohort profiles and an optional private beginner solve count. Definitions carry gridSize (rows) and gridWidth (columns); absent gridWidth means square. StrandsGenerator fills the dimensions exactly with disjoint bending paths. Every cohort receives one canonical letters matrix. BoardController derives the aspect and retains its authored square/rectangle panel poses.

Classic uses the saved progression.solves count (all completed boards, including Duel wins; tutorial practice does not count). Below 10 solves, each player gets a private 15-second Standard queue and round with only themselves and simulated companions. Exiting an unfinished board does not advance the admission threshold; existing players with 10 or more solves go directly to the shared queue. There is no new profile field or data reset.

| Classic rounds | Board | Words | Word length | Placement |
| --- | --- | --- | --- | --- |
| Below 10 solves | 5x5 | Exact coverage, variable | 3+ | bending adjacent paths |
| 10+ solves | 7x7 | Exact coverage, variable | 3+ | bending adjacent paths |

PuzzleCatalog.BeginnerThemes contains five curated familiar-word pools (Animals, Yummy Food, Let's Play, At Home, Outside), separate from the 34 full themes. Seeded selection and canonical placement still vary each round. Beginner companions use the existing verified-headshot and adaptive-pacing logic, with no challenger allowed to finish first. Each private pool prepares 2-11 bots, levels 1 through owner level + 2, with disjoint IDs below -2000000000. Ready bots join one at a time with deadline-aware spacing (at least 0.45 seconds), so all eleven can enter the 15-second countdown rather than being limited to a few arrivals. Unavailable headshots never block the round or admit default portraits; a round can start with fewer companions. Private pools are independent of the public 12-slot filler budget, including in full real servers. Their lobby is frozen during play; final portraits stay until Exit, and cancellation/disconnect/generation failure/shutdown disposes private ownership.

Standard uses a 5x5 beginner board below ten saved solves and a 7x7 board afterward (columns x rows). BuildClassicDefinition applies this to private queues and solo/replay admission from authoritative saved solves. Every cell belongs to one hidden theme word or the spangram; word counts vary with the exact-cover selection. No skill averaging, filler letters or overlapping answers remain.

QueueUpdated is sent per recipient. Beginners see only their own private roster/count/deadline (empty before joining), while graduates see the public queue. A server publication revision increases across both streams, so graduation cannot make the client reject a lower private/public queue revision. Existing authored Main.Queue, transitions, cards and round membership rules remain in use.


Each member's found words, hints and completion are independent. The server validates membership, round ID and the canonical path before changing progress. It does not hydrate authoritative state from client-reported found words. Wrong/duplicate submissions award nothing. A member may complete while others continue, pause locally, or explicitly leave. A round is removed after its final real member leaves and its bots are released to requeue. Active Standard rounds are not resumed across server departures; saved XP, hints and statistics persist.

QueueBots is a pure session scheduler used by Standard queues and the DuelBots adapter. GameConfig.Bots enables a public server-wide pool with a 12-slot budget. Its target is uniformly random from 2 through the spare slots after counting all connected real players (minimum clamped to available slots), rerolled for each next cohort, on real population changes and every 60-120 seconds. Empty/full real servers admit no new bots; existing opponents remain through the end of their round. Reconciliation retires only idle/queued bots. Active opponents can remain above a reduced population target until every real member finishes or leaves; no new bots are created while above that target. New bots become due after 2-3 seconds. One shared admission gate budgets randomized gaps against the remaining countdown and pending bots, never below 0.45 seconds. All eleven ready bots can join within 15 seconds. Delayed ticks and simultaneous avatar completion still admit at most one per step. They respect an existing deadline and never slip into an expired cohort. Bot-only queues drain without puzzle generation and requeue after 1-3 seconds.

Each bot has a reserved negative session userId starting at -1000000000, generated name/level, isBot flag and thumbnailImage. QueueService tries up to four random public Roblox account headshots with GetUserThumbnailAsync; only a ready image admits the bot. Exhausted attempts use the cache of up to 64 verified headshots; when that cache is empty the worker retries after 10-20 seconds while the bot remains outside the queue. Hardcoded account/default-profile fallback images are removed. The image travels in queue and round snapshots, and InterfaceController/BoardController render it directly rather than requesting the fake userId. UIEffects.SetPortraitImage forces ImageTransparency to zero and hides an optional authored Profile overlay. Bot identity is never mapped to a Player or profile. Avatar requests cannot resurrect an evicted bot.

Bots use varied Roblox-style handles (plain names, prefixes, suffixes, underscores and optional short numbers), unique within the active pool. Each round observes every human's accepted-word count and recent solving intervals. After at most one opening find, most bots trail the median active human progress by 0-2 words; 35% of public rounds designate at most one challenger, capped one word ahead of the leading active human. A challenger can finish only when a human has reached the last word; other bots cannot finish before a human. First attempts wait 18-40 seconds, later delays adapt to measured pace, word length, individual variation and occasional pauses. A shared 2-5-second gap prevents simultaneous bot solves, including after slow ticks. Idle humans cannot cause a bot to rush through the board; bots keep their existing round until its humans finish or leave. These are simulated companions, with no profile/XP/reward writes. QueueState validates the stored path. The expected-round guard on release and generation-failure/shutdown cleanup remain unchanged.

Each accepted canonical word find records member.foundOrder[word] using the increasing server round revision. Snapshots copy this map. BoardController sorts each word's finders by that value, earliest on the left, displaying the earliest three remaining solvers and +X afterward. A departed finder promotes the next solver; duplicates, hints and roster reordering cannot replace the accepted solve order. Legacy/tutorial snapshots without an order map retain roster order as a fallback.

## Solo modes and supported definitions

GameController updates Mini/Jumbo/Hardcore Play buttons at startup and on each accepted profile snapshot. Play.Locked is visible below the required level. Play.TextLabel always uses scaled Size (0.587, 0.6); locked labels use Position (0.634, 0.5) and Left alignment, while unlocked labels use Position (0.5, 0.5) and Center alignment. Authored anchors stay intact, and text remains Level N or PLAY.

Home.Gamemodes.Mini/Jumbo/Hardcore.Play use Activated and send QueueAction.StartSolo with the mode. QueueService validates profile readiness, tutorial/Duel/queue exclusion, and the server-derived XP level. It generates one fresh puzzle and creates a round containing only that player, returning the board immediately. It does not add a queue member, change a queue deadline, or broadcast the solo board. Duplicate starts return the same active round. Solo exit/disconnect releases membership. RoundBusy replaces StandardBusy and blocks both sides of Duel challenges plus tutorial starts for queued, shared-round and solo players.

| Mode | Grid | Words | Directions | Entry |
| --- | --- | --- | --- | --- |
| Standard | 5x5 beginner; 7x7 graduate | exact cover | bending | private below 10 solves; shared afterward |
| Mini | 5x5 | exact cover | bending | immediate solo, Level 5 |
| Jumbo | 8x8 | exact cover | bending | immediate solo, Level 10 |
| Hardcore | 7x7 | exact cover | bending | immediate solo, Level 20 |
| Duel | 7x7 | exact cover | bending | existing 1v1 challenges |
| Timed | 7x7 | exact cover | bending | definition only; no launcher |

PuzzleCatalog contains shared theme pools. BuildDefinition explicitly rejects retired/unknown modes. Seeded selection varies themes, words and placement; StrandsGenerator partitions a full-grid path into disjoint answers, with a guaranteed spanning answer. TutorialService uses BuildTutorialDefinition for the private CAT/DOG/FOX 3x3 bending practice board. The former Classic catalog and GameService/ProgressionService implementations, legacy star helpers, level selector and unused summary flow are removed.

PuzzleCatalog contains 34 full pools plus five separate beginner pools, including Roblox, Brainrot, Obbies, Tycoons, Pet Collecting, Football, Basketball and Racing, plus expanded Sports. Each added pool qualifies for all six mode definitions after their word-length filters, with variable word counts that exactly cover each board. These packs enter the existing seeded rotation automatically; there is no pack-selection remote/UI. ModeTests isolates each new/expanded pool and generates every supported definition to catch packs that would otherwise be silently excluded.

Hardcore submits incorrect selection paths after the normal wrong-word sound/effect. QueueState.FailSelection verifies a contiguous, non-repeating in-bounds bending path of at least three cells, excludes correct theme spellings, and records failure once. Failed or completed rounds reject further words/hints and never grant a completion reward for failure. GameController locks the board and opens GameOutcome with "Wrong word!", the actual found-word count/earned XP and Play/Home. No Game.Exit or Subtitle is needed to recover from a failed round. Mini and Jumbo retain ordinary mistake feedback without losing. Solo wins receive the normal per-letter XP, completion XP and mode-based pieces; their statistics use their own mode buckets.

## Server sky and fixed camera

ServerBootstrap starts Operations.InitEnvironment before remote setup/player loading and stops its Heartbeat connection at shutdown. Operations creates or reuses Workspace.CamPart, an anchored invisible 1x1x1 Part with collision, touch, queries and shadows disabled. Its position is (-225.271, 136.93, -519.269); CFrame.fromOrientation applies the Studio Orientation (15.309, 40.884, 0) in degrees. ReplicatedStorage's CamPartCFrame attribute carries that same pose independently of Workspace streaming.

The client Camera module holds CurrentCamera in Scriptable mode at this server pose, keeps FOV 40, and sets Focus 100 studs ahead. A named render binding runs after Roblox's default camera to cover respawns and CurrentCamera replacements. Attribute arrival applies immediately, so late joins and a streamed-out anchor do not leave the view attached to the character. Repeated setup replaces the prior binding; Main.Destroying removes the binding and attribute listener. GameController remains the only caller.

Operations reuses Terrain's existing Clouds instance or creates one if absent. Every 0.25 seconds it advances a sine-eased blend between four daylight presets, taking 180 seconds per transition (12 minutes per loop). Cloud cover spans 0.28-0.58 and density 0.32-0.48; color, Lighting.Brightness, Ambient and OutdoorAmbient blend with them. GeographicLatitude is 35. The replicated TimeOfDay stays between 11:00 and 15:30, including across loop boundaries and long frame stalls. No night setting or old InitDayNight loop remains. Existing Sky/Atmosphere instances are preserved. The property contracts follow Roblox's [Lighting](https://create.roblox.com/docs/reference/engine/classes/Lighting) and [Clouds](https://create.roblox.com/docs/reference/engine/classes/Clouds) APIs.

Client code never assigns GuiService.SelectedObject or captures UI focus. GameController changes views without selecting or clearing controls; TutorialView adjusts Selectable availability without choosing a focused button. BoardController.KeyboardMove updates its own cursor/path only, while manually selected tiles may still update the cursor through SelectionGained. Input reads the current selection to avoid handling board shortcuts over other controls.

## Authored HUD contract

`Main.Home.ButtonBar.Shop` was removed from the authored UI. ProgressionController's optional lookup and nil-safe connection already support its absence. No replacement launcher is generated. `Main.Frames.Shop` has also been removed; `Game.Hint` directly prompts product 3714515983 for one hint at zero inventory.

StarterGui contains sibling ScreenGuis Main and GroupIntro. With automatic character spawning disabled, ClientBootstrap waits for initial game replication and mounts one copy of each authored ScreenGui into PlayerGui only when absent (rechecking after template waits). Existing copies are reused; no device-specific HUD is selected. Missing/wrong-class templates fail explicitly rather than generating replacement UI. Main is disabled and ResetOnSpawn=false is set before parenting new screens. Main stays disabled while the retained Social.GroupIntro animation preloads its assets, then the completion callback enables Main and the player's configured music. The intro waits up to 12 extra seconds for the first profile snapshot; server-dependent actions remain disabled until a snapshot arrives. Both ScreenGuis use ResetOnSpawn=false, and device handling retains the authored screen orientation. UI must remain present in Studio; this repository does not generate the authored screens.

Music uses the existing client Audio system: tracks 72191087451264, 133244468349763, 9045766377 and 136037234851815 play in that order and loop at volume 0.2. Playback starts after GroupIntro and respects the saved Music setting.

ServerBootstrap sets Players.CharacterAutoLoads=false before any service/module waits. No LoadCharacter/LoadCharacterAsync call is made, so normal joins have a Player but no avatar, falling physics or respawn loop; no baseplate is required. Before waits, server and client bootstraps also subscribe to CharacterAdded and root ChildAdded, anchor any existing/late/replaced HumanoidRootPart and clear its linear/angular velocity. This fallback covers Studio's already-created characters or another script explicitly spawning one. The server deduplicates early player bindings and sets Player.ReplicationFocus to Workspace.CamPart before profile loading. Camera continues to use the replicated pose without needing a character. Roblox documents [CharacterAutoLoads](https://create.roblox.com/docs/reference/engine/classes/Players/players), [StarterGui copying on spawn](https://create.roblox.com/docs/reference/engine/classes/StarterGui/GetCore) and [server replication focus](https://create.roblox.com/docs/reference/engine/classes/Player/ReplicationFocus).

```text
PlayerGui.GroupIntro                 existing group intro animation
PlayerGui.Main
  Home
    Background
    GameIcon                         gentle rotation around authored Rotation
    SelectModeLabel
    ButtonBar
      Daily                        GuiButton -> Frames.DailyRewards (DailyReward / Daily aliases retained)
      Duel                         GuiButton -> Frames.DuelLobby
      Leaderboard                  GuiButton -> Frames.Leaderboards / Leaderboard
      Settings                     GuiButton -> Frames.Settings
    Gamemodes
      Standard
        Play                         joins queue at any player level
        Waiting                      TextLabel: N Waiting
          Frame
            UIStroke                 Thickness 3 <-> 1, continuously
      Mini
        Play
          TextLabel                  Level 5 until unlocked; PLAY starts solo
      Jumbo
        Play
          TextLabel                  Level 10 until unlocked; PLAY starts solo
      Hardcore
        Play
          TextLabel                  Level 20 until unlocked; PLAY starts solo
    LevelBar
      Star                           image with level text
      XP                             current XP / increasing level requirement
      FillBar
        Fill
  Game
    Background
    Bonus                            authored, no new reward logic
    Title                            STRANDS, MINI, JUMBO, HARDCORE, 1V1 STRANDS or TIMED
    Subtitle                         theme title (Hardcore rule/loss message); hidden for Duel/Timed
    Streak                           authored
    BoardPanel
      UIAspectRatioConstraint        columns / rows
      UICorner
      UIStroke
      PuzzleGrid                     runtime letters and selection/found/hint lines
    WordPanel
      Title
      Words                          local found count / word count
      Container
        ScrollingFrame
          UIListLayout               retained; SortOrder = LayoutOrder
          Word_<WORD>                cloned WordPanelTemplate
    OneVsOneMode
      YouMugshot
      EnemyMugshot
      YouUsername
      EnemyUsername
      YouScore
      EnemyScore
      XP
      YouWinRate                     own wins / all Duel results as a percentage
      EnemyWinRate                   opponent wins / all Duel results as a percentage
    TimedMode
      UIAspectRatioConstraint
      UICorner
      UIStroke
      Icon
      TimeLeft
    Exit                             optional legacy child; absent in current Game
    Hint
      TextLabel
      Owned                          badge hidden at zero hints and before profile load
        TextLabel                    server-owned hint count
    LevelBar
      Star
      XP
      FillBar
        Fill
  Tutorial                      authored movable tutorial panel
    PopScale                         UIScale; restored on completion/Skip
    UIAspectRatioConstraint
    UICorner
    UIStroke
    Content
      Title                          current tutorial heading
      Paragraph                      MaxVisibleGraphemes typewriter
    Skip                             authored GuiButton; always usable during tutorial
      TextLabel
    Icon                             four-pixel talking bob while typing
  TutorialSpotlight                  temporary overscan mask, four input-blocking panels plus rounded corner strips
  Frames                             outer modal roots start hidden at Size (0, 0)
    Shop                             removed; optional legacy hierarchy only
      UIAspectRatioConstraint, UICorner, UIStroke
      Frame                          content only; not animated/resized by modal controller
        UIListLayout
        One                          5 hints
          Buy, Icon2, Title
        Two                          15 hints
          Buy, Icon2, Title
        Three                        30 hints
          Buy, Icon2, Title
      Footer.Title
      Quit, Title
    Countdown, CustomFrame
    DailyRewards
      UIAspectRatioConstraint, UICorner, UIStroke
      Requirements.Title             daily streak / next reward details
      Claim.TextLabel                CLAIM / CLAIMED / CLAIMING... / LOADING...
      Quit                           close outer modal
      Timer                          plain countdown; green 00:00 when claimable
      Title                          authored screen title
    DuelLobby
      UIAspectRatioConstraint, UICorner, UIStroke
      Container.ScrollingFrame
        UIListLayout                 preserve authored padding/layout
        DuelPlayer_<UserId>          clones of assets/Assets.1v1Template
          UICorner, UIStroke         authored row decorations
          Request                    Activated -> challenge this account
          Mugshot.UIStroke           queue palette / 30% darker matching stroke
          Username
      Quit, Title
    DuelRequest
      UIAspectRatioConstraint, UICorner, UIStroke
      Green.Icon                     accept current incoming challenge
      Red.Icon                       decline current incoming challenge
      Mugshot                        current challenger headshot
      Title, UserName                1V1 REQUEST / @challengerUsername
    DuelOutcome
      UIAspectRatioConstraint, UICorner, UIStroke
      FillBar.Fill                   current profile XP, shared gold level-up effect
      Home                           animated return to Home, once per shown result
      WinnerIcon, LoserIcon          mutually exclusive, driven by isWinner
      Title                          YOU WON! / YOU LOST!
      CurrentXP, LevelTheme          profile level/XP and board theme / 1v1
      Words, XPWon                    personal foundCount/wordCount and xpEarned
    GameOutcome
      UIAspectRatioConstraint, UICorner, UIStroke
      FillBar.Fill                   current XP, minimum 0.1, shared gold level-up effect
      Play                           exit then replay current mode
      Home                           exit then return Home
      Quit                           dismiss this popup
      Icon2                          authored completion icon
      Title                          Complete!
      LevelTheme                     puzzle title ? Themes / solo mode
      Words                          found / total Words
      XPWon                          +server-awarded round XP
      CurrentXP                      Level N ? XP / required XP
    Leaderboards
      UIAspectRatioConstraint, UICorner, UIStroke, Title, Extra
      WordsFound                     default visible panel
        One, Two, Three              first / second / third place, resolved by name
          Mugshot.UIStroke           gold / silver / bronze with darker outlines
          Data, Place, Username
        WordsFound, 1v1Wins, Level    tab buttons
      1v1Wins                        same slots and tab buttons; initially hidden
      Level                          saved XP levels; same rows/tabs, initially hidden
      You                            local player score and personal rank for selected tab
      Quit                           closes Leaderboards from any tab
    Levels, PurchaseFrame, Statistics
    Verify
      UIAspectRatioConstraint, UICorner, UIStroke
      Frame
        UIListLayout
        Requirements                 two authored requirement rows
      Okay                           Activated -> GroupService:PromptJoinAsync
        TextLabel
      Quit, Title
    Settings
      UIAspectRatioConstraint, UICorner, UIStroke
      Frame
        UIListLayout
        Music, SFX, 1v1
          UICorner, UIStroke, Icon2, Title
          Toggle                     Activated; On/Off state
            UIStroke
            TextLabel
      Quit, Title
  Queue                              authored queue screen
    Container
      UIAspectRatioConstraint        retained
      UIGridLayout                   retained; SortOrder = LayoutOrder
      QueuePlayer_<UserId>           clones of Assets.PlayerTemplate in join order
    Exit                             authored GuiButton -> LeaveQueue
    Background                       retained
    Subtitle                         Standard Mode (15s), using shared server deadline
    Title                            retained authored title
  GameTransition                     temporary white overlay during mode entry/exit
  RoundPause                         runtime pause frame, Resume, Leave round
```

The authored square BOARDINFO frame (BoardInfo or legacy BoardPanel) always has aspect 1. The generated gameplay grids are square; the small 3x3 tutorial fits square cells inside that square frame. Legacy non-Strands fixtures use their actual grid dimensions. Strands preserves the authored board/word-panel positions. For legacy fixtures at aspect 1, BoardPanel.Position is {0.387,0},{0.5,0} and WordPanel.Position is {0.667,0},{0.5,0}. At aspect 1.5, the positions are {0.39,0},{0.5,0} and {0.75,0},{0.5,0}. Other nonsquare grids use those wider-panel positions with their actual aspect. Classic/Standard generates 5x5 beginner or 7x7 graduate grids; the renderer follows the server dimensions. Authored panel sizes, anchors, constraints and word-list layout remain in place.

```text
ReplicatedStorage
  Assets
    PlayerTemplate                   Frame cloned once per queued player
      UIAspectRatioConstraint
      UICorner
      UIStroke
      Star
        Level                        server-derived level at queue join
      YouMugshot                     Roblox headshot
      Title                          display name
    WordPanelTemplate                Frame cloned once per word
      UICorner
      Word                           TextLabel; discovered word, no strike-through
      BreakLine                      always-visible authored divider
      PlayerTemplate                 ImageLabel/ImageButton, hidden source template
        UIStroke                     darker than portrait background
      FoundPanel
        UIListLayout
        Finder_<UserId>              clones for round members who found this word
  shared
    ui
      UIEffects                      retained for the authored Main.FX LocalScript
```

Each finder receives a random color at about 80% saturation (HSV saturation 0.75 to 0.85, value 0.85 to 0.95), darker stroke and Roblox headshot. BoardController caches the color by user ID for the whole round, including repeated progress updates, row sorting and all found words; Build clears that cache for the next round. Local finds add the local headshot, keep the word text visible, set WordPanelTemplate.BackgroundColor3 to the completed line colour (BackgroundTransparency 0.75; the line remains 0.18), and move the row above all unfound rows, retaining the puzzle order within each group. Unfound rows keep their authored template background and stay visible throughout the round. BreakLine stays visible throughout; others' finds add their headshots without solving the local player's word. Leaving removes that player from the active roster/portraits. Optional sound, modal and Duel decoration nodes degrade safely. Required Home/Game panels and WordPanelTemplate report explicit missing-path errors.

The popup alerts system is removed: no generated notification stack, dispatcher, timer, pointer blocker or toast animation remains. The old purchase-notification RemoteEvent is removed; ProcessReceipt still saves the grant before returning PurchaseGranted and publishes the updated profile through StateUpdated. Rewards refresh their authored views, and tutorial completion continues retrying saves silently. Authored hint counts and reward-availability badges remain part of their owning screens.

InterfaceController starts shared.ui.UIEffects.AnimatePattern for each authored Home.Pattern, Game.Pattern and Queue.Pattern ImageLabel/ImageButton. ImageTransparency begins at 0.98. Home uses the quiet option: 0.96 over six seconds with Sine/InOut, then reverses. Game/Queue retain 0.92 over four seconds each way. All repeat indefinitely. Duplicate setup does not restart an active loop, and destroying the image cancels its tween. Missing patterns are ignored. RevealGame excludes Pattern alongside Background so the decorative layer retains its geometry during board entrances and exits.

Board feedback lives in shared.ui.UIEffects. A short scale/reveal animation introduces the runtime grid and staggers its letters; input unlocks after that reveal. Rebuilding cancels the old reveal before replacing its tiles, and delayed completions cannot unlock a different board. Panel positions and sizes retain the authored layout contract above.

Strands letters use Ubuntu Bold in bounds 54% of a cell, maximum text size 56, with white rounded faces at 76% of the cell size. Each face has a one-pixel black UIStroke at 0.82 transparency and a faint offset shadow. Selected faces show a grey gradient; solved faces use the accepted word's palette color with a matching pale inset rim. Faces remain grid siblings below letter buttons, so both ScreenGui ZIndexBehavior modes keep glyphs visible. PuzzleGrid is centered at (0.5, 0.5) and fits 98% of the authored square frame; no generated tray or bottom text exists.

Strands links bridge the edges of consecutive tiles, leaving glyph centers clear. An outer segment in the word's color and a pale rounded core follow every bend, including diagonals; the active drag stays grey. Hint tile faces, segments and cores pulse white-to-gold together without restarting on drag refresh. Input samples intermediate cells, ignores gaps, supports backtracking and rejects repeated cells within a single path. Success particles and wrong-word shake/sounds remain; no text footer is generated. Legacy fixtures retain the straight-line renderer.

All gameplay is timed. `GameConfig.RoundSeconds` owns the defaults: Standard/private/solo 180 seconds, Mini 90, Jumbo 300, Hardcore 180, Duel 180 and tutorial practice 180. Normal rounds start their server deadline at creation (queue waiting excluded, entry animation included); Duel starts after its countdown. Snapshots carry `timeLimit` and `expiresAt` from `Workspace:GetServerTimeNow()`. Server expiry ends unfinished members once, preserves already earned XP, rejects late words/hints and grants no completion bonus. Completed members retain their result and remaining time. Pause, shop and tutorial guidance do not stop the clock. Standard/solo expiry opens the existing GameOutcome with "Time's up!", partial progress and Play/Home. Duel expiry compares theme counts; the higher count wins, equal counts draw without wins/losses or outcome rewards, with Rematch/Home available. Tutorial expiry offers a fresh practice retry without completing onboarding or changing inventory/XP. The speed bonus affects round score only; no speed-based XP/inventory rewards, timer products or extensions are introduced.

Finder rows show at most three PlayerTemplate clones for real players and bots combined. If more members find the word, BoardController clones ReplicatedStorage.Assets.Exceeds into that word's FoundPanel, orders it after the portraits and sets its direct TextLabel.Text to +<finderCount - 3>. The same Exceeds instance updates on subsequent snapshots and is removed at three or fewer finders. Its authored geometry is preserved. Exceeds is resolved while building the board; progress updates do not yield to wait for assets.

## Queue presentation and game transitions

Home and Queue now share the white transition system with Game. Home's icon, mode group, button bar, heading and LevelBar shrink/move out with staggered poses, then spring back to their authored positions and scales on return. Queue's container, subtitle and Exit have matching motion. Menu reveals last 0.75 seconds while the 0.8-second white fade clears; input stays locked through both. Queue rosters received during entry are applied when it finishes, and cancellation restores geometry without reopening an old view. Existing Pattern/Background motion, Game transitions and immediate tutorial practice entry remain intact; practice completion uses the normal animated Home return. Queue cards, new finder portraits and Exceeds pop in; Home/Queue/pause/modal buttons have hover/press/Activated feedback. Button pulses respect authored UIScale values and cannot interrupt exit tweens. Reward modals animate their outer frame under the contract below.

Every direct GuiObject under Main.Frames initializes hidden with Size (0, 0), including late-added frames. ProgressionController animates the outer modal itself to Size (0.33, 0.33) on every device with a 0.44-second Back/Out tween; closing shrinks it over 0.32 seconds before hiding. Preserve its authored background, position, anchor and child Frame geometry/visibility. Cancel overlapping tweens and invalidate stale close callbacks across reopen/rebind. Main.Frames.BackgroundTransparency initializes at 1 and tweens over 0.22 seconds with Sine/Out to 0.6 while any direct modal is visible, then back to 1 after the last closes. Visibility observers cover external changes and late-added/removed modals; switching modals retains dimming, superseded tweens cancel, and teardown restores transparency 1. These observers are separate from temporary CustomFrame button connections. Duel modal readers also start at the outer root. Main.Frames.Shop and Main.Home.ButtonBar.Shop are absent. Game.Hint uses owned hints through the existing server endpoint; at zero hints it directly prompts developer product 3714515983, granting exactly one hint. GameConfig.Meta.DIRECT_HINT_PRODUCT owns its ID and amount. The purchase prompt requires an active unfinished puzzle with an unhinted answer, preserves the board and blocks underlying interactions while open. Repeated taps cannot open overlapping prompts; matching cancellation/completion, prompt errors and teardown release the guard. Only the server receipt handler grants hints, never PromptProductPurchaseFinished. Tutorial hints remain free. Legacy hint products (3573028208=1, 3573028342=5, 3573028459=15, 3711566945=30) retain their grants for delayed receipts, including save-before-acknowledgement and duplicate protection. Optional legacy Shop bindings remain nil-safe; no replacement Shop is generated.

GameOutcome is the result popup for Standard/private beginner and Mini/Jumbo/Hardcore wins, timeouts and Hardcore wrong-word losses. It shows Complete!, Time's up! or Wrong word! respectively, with Play/Home for every outcome. GameOutcome.LevelTheme shows only `Theme: <theme>` (for example `Theme: Fresh Air`), without a mode suffix. DuelOutcome keeps its theme/mode separator; Level/XP labels retain ASCII ` | `. GameController waits for the reveal and 0.55 seconds of final-word feedback, then opens it once per local finished round; opponent completions, tutorial, Duel and stale/exited rounds do not open it. Direct children are Title, LevelTheme, Words, XPWon, CurrentXP, FillBar.Fill, Play, Home and the authored Icon2. Show the prefixed puzzle theme, local found/total, member.xpEarned and current profile level/xp/requirement. QueueState snapshots include session-only member.xpEarned, accumulated by QueueService only alongside accepted per-letter XP and the once-only completion bonus; bots/duplicates/hints alone add nothing and no profile schema changes. Both outcomes use Interface.PlayOutcome: Words fades in and counts from zero to the actual found/total, XPWon fades/scales in and rapidly counts awarded XP, then FillBar/CurrentXP reveal the captured pre-round progression before tweening to the final progression. GameController captures progression at round entry or Duel countdown. The shared bar retains its minimum 0.1 and gold level-up effect; available Play/Home buttons pop in last and reject actions until ready. Later accepted snapshots update the target without restarting the count-up. Closing, destroying or replacing the outcome cancels pending stages/tweens and restores authored visibility, transparency and scales. Play exits the completed server round successfully, then joins Classic or starts the same solo mode directly. The completed board stays visible until one white transition mounts Queue (Classic) or the next solo board; Home is not shown between games. Failed exits retain the completed board; failed replay admission returns Home. Home exits and returns without replay. GameOutcome has no Quit binding or dismiss-only action. Pending/transition/round-ID guards prevent duplicate or stale actions. GameOutcome uses the outer-frame 0.33 modal system, and screen changes cancel hidden modal tweens.

Verify uses direct children Main.Frames.Verify.Okay and Quit. Okay.Activated calls GroupService:PromptJoinAsync for Meta.GROUP.Id (34241464), without a prerequisite group-info lookup or browser fallback. Suppress overlapping prompts and allow retry after a prompt error. Retain the existing membership verification and server-owned group reward request; Quit closes the outer Verify modal. The inner Frame.Requirements rows remain authored content. Verify automatically queues after the local player completes their first normal puzzle entered with zero saved solves, then opens on an unobstructed Home after the result/return transition. Tutorial completion alone does not qualify ordinary players; existing members and players who already claimed the group reward are excluded. The configured Tutorial.ReplayUserId owner (1790165114) also sees Verify after finishing or skipping the tutorial replay, even if already a member or previously rewarded. This override changes presentation only; the server group reward remains once-only. The session-local invitation opens at most once, waits through games/queues/tutorial/other modals, and cancels stale callbacks on controller teardown/rebind. Opening Verify itself performs no group-info lookup or native join prompt; Okay remains the explicit join action.

Settings binds Main.Frames.Settings.Frame.Music.Toggle and SFX.Toggle, with Quit on the outer Settings frame. Both default On for missing/new settings and preserve saved Off preferences. Toggle.TextLabel (also accepting the authored spelling Textlabel) displays On or Off. On background RGB (75, 202, 53), toggle UIStroke (31, 154, 31); Off background (202, 61, 51), stroke (154, 28, 28). Only the toggle and its direct border change; retain card and label strokes. Create a missing toggle border, tween colors over 0.18 seconds, and update the UIEffects base color/cancel its previous highlight so hover/press cannot restore stale state. Activated changes the local snapshot/audio immediately and sends the existing allowlisted UpdateSetting remote; incoming snapshots refresh the labels/colors and server data persists both booleans.

Calm feedback accents use short, self-cleaning UIStroke highlights on confirmed word rows, XP gains and board completion. Button activation uses only its scale pulse; it never adds or brightens a UIStroke. Hover/press motion and authored borders remain intact. Confirmed words ripple a small pulse along their letters over 0.22 seconds and gently pulse the found-word counter. LevelBars ease ordinary XP changes over 0.5 seconds. On a level increase, both fills tween to gold and Size (1, 1) over 0.35 seconds, hold for 0.12 seconds, then tween to Size (0.1, 1) and their authored green over 0.4 seconds before filling to the latest remaining XP. The star also accents. Initial profile loads do not replay old level-ups; duplicate snapshots do not restart effects, and updates during gold/reset coalesce into its final XP target. Cancellation invalidates old callbacks. Pulse overlap cancels safely, temporary scales/borders are removed, authored scale/stroke values are restored, and screen transitions take priority over direct panel pulses. These effects add no input blockers, focus changes, gameplay delays or perpetual loops.

InterfaceController binds Main.Queue/Container/Exit/Subtitle and clones ReplicatedStorage.Assets.PlayerTemplate. It retains the authored UIGridLayout, aspect constraint, card styles and background. Each card's YouMugshot receives a colour from a shuffled 30-colour HSV palette (saturation 0.75-0.85, value 0.85-0.95) and its existing UIStroke receives that color blended 30% toward black. Color is chosen only when cloning the card, so roster updates retain it; a fresh queue entry rerolls it. Cards are keyed by user ID and ordered by queue membership: refreshes update name/level, departures destroy only that card, and thumbnail callbacks cannot overwrite a removed or replaced entry. Leaving/mounting Game clears the runtime cards. On dispatch the visible cohort stays on Queue until full white, while Home's waiting count immediately follows the next live queue.

GameController runs UIEffects.TransitionToGame for Standard, Mini, Jumbo, Hardcore and Duel. All QueueService round payloads use this path, including future Timed payloads; tutorial practice retains its immediate guided entry. A temporary input-blocking white Frame spans beyond inset edges inside Main; 0.7-second Sine fade-in reaches full white before Game is mounted, then 0.8-second fade-out reveals the game. UIEffects.RevealGame slides BoardPanel and WordPanel from opposite sides, optional title/subtitle from above, and LevelBar from below. Hint and any legacy Exit grow from zero with Back easing; other visible controls settle in with small staggered offsets. Background, Pattern and hidden mode panels stay unchanged. Final authored positions, sizes and existing UIScale values are preserved, and temporary scales are removed. The board's staggered letter reveal remains active.

Game.Exit is absent from the current authored hierarchy. Outcome Home or pause Leave requests server Exit (or Duel abandon), then UIEffects.TransitionToHome reverses the same panel poses and stagger: controls shrink first and panels slide away. The 0.7-second white fade starts 0.2 seconds into that reversal; at 0.9 seconds Home replaces Game under full white, and the outgoing geometry restores while hidden. White fades out over 0.8 seconds. Queue.Exit uses the same white/Home transition without reversing hidden game panels. Manual pause remains available; its Leave button uses the same round exit path. A rejected Exit leaves the board usable and displays the server error.

Input, pause, Play, Exit and meta prompts stay locked through transitions; normal board input unlocks after the 0.9-second entry panel reveal without assigning UI focus. Round revisions and Duel progress arriving during entry update the cached roster and are applied after mounting, including Duel scores. A Duel start event does not bypass the fade lock or reactivate a completed match. Successful exits ignore that round's later packets. Changing the view cancels the active animation, restores geometry and invalidates delayed callbacks, so an old transition cannot mount a stale screen. Solo modes still start without joining a queue.

Portrait colours use UIEffects.NewPortraitPalette: 30 evenly spaced hues shuffled without replacement, with no immediate repeat between decks. Queue cards retain their choice until removed; a round caches the same colour per finder across all words. New queue entries and new boards reshuffle.

## Tutorial ownership

`GameConfig.Tutorial.ReplayEveryJoin` is `false`: saved completion/Skip is respected, and only players who still require onboarding receive the tutorial. The optional replay mechanism remains available for future testing. DataService initializes a server-owned TutorialReplayPending attribute once after loading the profile. Snapshots and Account mirrors present pending tutorial state while that flag is set, and TutorialBusy blocks real queues/solo rounds/duels. TutorialService checks the effective session state so replay still validates practice paths and completion. Skip/completion clears the flag for this session; saved tutorial completion history remains intact. Respawns and repeated snapshots do not re-arm it. The current false setting does not force repeat onboarding on completed accounts.

GameController waits for both GroupIntro completion and the first profile snapshot before Tutorial.Start. With the testing override off, existing players see normal Home. New players enter Main.Game immediately; queue revisions continue caching during practice and cleanup restores the latest live count. Tutorial play routes through TutorialAction, never QueueAction.Join. TutorialBusy gates Standard joins, solo starts and both sides of Duel challenges server-side. The tutorial also centralizes board input, pause, modal/reward locks and which controls are available for manual navigation.

Tutorial.luau owns Loading -> FindCat -> TryHint -> FindDog -> FindFox -> Win -> HomeCongrats. Start opens Game and requests practice automatically. Successful loading builds the grid and goes straight to Make CAT!; failed requests retry in Game at two-second intervals. Finding CAT goes directly to the free Hint step, then Make DOG! and Make FOX!. Every word accepts either traversal direction. No example portrait is inserted. The free hint highlights DOG through normal board presentation, even with zero inventory. The optional legacy Exit stays hidden through the win message and is restored at completion or Skip. Timeout retry requests a fresh board without visiting Home.

TutorialView.luau adapts the Kingdom Wars TutorialController spotlight: four rectangles partition an overscanned screen using shared integer edges, with an input blocker over informational openings. Disjoint one-pixel corner strips turn the opening into a rounded rectangle, with fractional edge coverage matching the outer dim opacity. Radius is twice the padding, capped at 24 pixels and half the opening dimensions, so the actual target stays uncovered. Corner objects are reused and their geometry is cached until the opening changes; they hide when there is no target and are destroyed with TutorialSpotlight. A single NumberValue opacity driver fades the outer panels and weighted corner coverage together: 0.22 seconds in with the panel reveal, 0.14 seconds out with collapse before changing targets. Skip disconnects the driver and destroys the active blockers immediately; passive Frame copies fade away for 0.14 seconds without intercepting input. The current authored control or word row stays clear. Tutorial keeps its authored AnchorPoint and uses scaled Position (0.5, 0.862). Hint steps tween to (0.5, 0.2), above the bulb, and tween back when the hint is used. Other highlighted targets may shift left to (0.4, 0.862) if they intersect the default frame/icon bounds. It returns to (0.5, 0.862) when the conflict ends. Authored size and resting PopScale remain unchanged. Step changes tween Tutorial.Size to UDim2.fromScale(0, 0) over 0.14 seconds, keep its position fixed until collapse, update the target/text/position while hidden, then tween Size back to the cached authored value over 0.22 seconds. PopScale follows the collapse so offset-sized children disappear too. Full-size geometry is cached for placement while collapsed, and per-frame layout cannot move the frame while either tween runs. Hint entry/exit includes Position in the 0.22-second opening tween, after collapse; per-frame layout cannot overwrite that tween, and Skip cancels it and restores the bottom position. First appearance grows from zero. Typing and action input wait for the opening tween; cancellation tokens prevent replaced or skipped transitions from reopening the frame. Text uses MaxVisibleGraphemes; Icon bobs four pixels over a repeating 0.09-second tween during typing. Headings and explanations use short, simple text. Informational steps advance two seconds after typing finishes; Word finds and Hint wait for the actual action. There is no continuation button or keyboard shortcut to advance explanations. Only Skip/current task can be selected manually during the tutorial; the view never assigns or clears UI focus. Replacing a step or closing the tutorial invalidates any pending reading timer. Board pointer starts exclude the tutorial panel and masked cells.

TutorialService creates a private GUID session using the existing CAT/DOG/FOX 3x3 bending onboarding definition (seed 1739). QueueState validates each claimed path against that canonical puzzle. Only a validated three-word clear accepts Complete; Skip may complete from any step. No practice action awards XP/currency/wins or consumes real hints. Both completion routes call DataService.CompleteTutorial, which records the first reason/timestamp and saves. Failed saves are reported for client retry; successful duplicate completion requests do not write again in the session. PlayerRemoving clears private practice state and request throttles.

After the win message, Tutorial.Advance marks the tutorial pending and collapses its panel/spotlight. TutorialView.Suspend hides the collapsed frame, keeping a transparent full-screen input blocker, while the GameController returnHomeAnimated callback runs the same UIEffects.TransitionToHome used by normal exits (reversed Game panels, white cover, Home reveal). Only its completion callback clears pending and shows HomeCongrats (Title "Tutorial done!", Paragraph "Have fun finding words!"). HomeCongrats passes no target: all dim panels and rounded corner strips hide and a transparent full-screen input blocker remains, so nothing on Home is spotlighted. The tutorial stays at (0.5, 0.862). It uses the same typewriter and two-second reading delay, then TutorialView.Collapse tweens Size and PopScale to zero before calling completion cleanup. The tutorial keeps input locked through the ending. Skip still immediately closes guidance, including during the final collapse. Cleanup cancels typing/icon motion/board gestures, destroys the spotlight and temporary controls, restores authored frame size/anchor/scale, control selectability and Exit, resets the tutorial position to (0.5, 0.862), and leaves Home visible. Generation guards prevent delayed Start/Word/Hint replies or a cancelled Home-transition callback from reopening the board or congratulations. Completion saves retry in the background until confirmed or the player leaves. Partial tutorial steps are session-local; unfinished players restart at Home after reconnecting.

## Network protocol

ReplicatedStorage.WordSearchBackendRemotes retains GetBootstrap, StateUpdated, TrackAction and UseHint and adds:

- FavouritePrompt (RemoteEvent): client sends no arguments to announce listener readiness; server dispatches once after the 900-second join timer and successful flag save. Clients cannot set the flag or deadline.
- TutorialAction (RemoteFunction): bounded Start, Word, Hint, Complete and Skip; separate private session IDs and per-action throttles.
- QueueAction (RemoteFunction): bounded allowlisted Sync, Join, StartSolo, LeaveQueue, Exit, Word and Hint requests. StartSolo accepts only Mini/Jumbo/Hardcore and checks the server-derived level. Word carries roundId, word and canonical candidate path; Hardcore also submits invalid paths for server loss validation.
- QueueUpdated (RemoteEvent): recipient-specific private/public queue count, ordered members (userId/name/displayName/level, plus isBot/thumbnailImage for bots), revision and absolute server deadline. RoundUpdated members also retain isBot/thumbnailImage for finder portraits.
- RoundUpdated (RemoteEvent): round ID, revision and participant progress; full canonical puzzle on entry/sync, scoped to that cohort.

Word and Hint requests require the current round ID. Word includes only word/path intent. Exit requires the matching round ID so a delayed exit cannot remove a later queue membership. Request rates are bounded per player/action. Client snapshot and round revisions reject older updates.

TrackAction now accepts only bounded analytics ClientFunnel events. Old solo BoardCleared/BoardStateUpdated/HintUsed actions cannot alter the new progression. UseHint is retained for Duel. Legacy ReplicatedStorage.Remotes.Events/Functions still host purchases, settings, meta rewards, leaderboard, Duel and rejoin endpoints.

Duel validates its own canonical paths. Its progress events include myFoundWords and opponentFoundWords. Result/forfeit packets also carry theme, wordCount and each recipient's foundCount and xpEarned. DuelService accumulates participant.xpEarned only with accepted word XP and the board completion bonus; duplicate/invalid finds and hints alone add nothing. The legacy myXP field now mirrors earned XP, while myPuzzlePieces remains the distinct piece reward. Partial losing/forfeit progress remains visible; winning by opponent forfeit does not invent completed words or completion XP. This is session metadata, not a profile schema change. Server membership attributes prevent playing Standard and Duel simultaneously. Departures resolve Duel results before profile release.

Duels binds the authored direct children of DuelRequest and DuelOutcome, without generic text fallbacks that could overwrite the title or hide the modal parent. Green/Red answer the current incoming challenge once and expiration hides the matching request. Mugshot uses the current challenger's Roblox headshot URI, avoiding stale asynchronous portrait callbacks. Countdown clears the incoming request and prior outcome. Active match IDs and result IDs reject stale/duplicate result packets. GameController ends board input on a matching result, then shows DuelOutcome after 0.55 seconds of feedback and completion of any entry transition, guarded by the current presentation version and match ID. The outcome chooses WinnerIcon or LoserIcon for wins/losses (including forfeits), hides both on draws and labels them DRAW!, and updates CurrentXP/FillBar from subsequent accepted profile snapshots without changing match XP. Home dismisses once and runs the existing game-to-home transition; exiting before a pending result invalidates its popup. Authored icon images, Home content and frame geometry are preserved.

## Data ownership

DataService owns WordHuntQueueData_v1 (player_<UserId>, schema 19), mutable profiles, strict migration/normalization, mirrors and serialized saves. See [PLAYER_DATA.md](PLAYER_DATA.md) for the exact whitelist and every client/Player representation. Level remains the only leaderstat. SocialService indexes progression.wordsFound in WordHuntQueueWordsFound_v1 and progression.duel.wins in WordHuntQueueDuelWins_v1. Saved progression.level is indexed in the existing WordHuntQueueLevels_v1 store, preserving its records. New indexes populate as existing players load their saved profiles; there is no offline backfill or profile reset.

The saved progression authority is level plus xp within that level. Schema 18 adds progression.wordsFound (default zero), a lifetime count incremented by DataService.RecordWordFound only after QueueService or DuelService accepts a new canonical word. It survives unfinished exits, saves and rejoins; duplicate/invalid claims, hints alone, bonuses, bots and tutorial practice never increment it. Missing counts are not inferred from board history. Solves replaces total board wins; progression.duel retains Duel wins/losses. Hints and puzzlePieces are top-level. Daily login rewards use lastClaimDay/streak. Prepared dailyPuzzle stores current UTC day, completion and a bounded found-word map, but no launcher or client mutation endpoint exists. Necessary settings/tutorial/once-only account flags, piece currency and receipt/session protection remain; arbitrary old roots, stats/activity/mode buckets, playtime rewards, retired archives and redundant totalXp/levelRewardsThrough are dropped during migration.

DataService.AddExperience derives total XP from level/xp, adds accepted XP, resolves the new pair and grants the difference in cumulative hint rewards. Reaching each even level (2, 4, 6, and so on) grants exactly 1 free hint; odd levels grant none. Daily claims grant 1 hint with no extra streak bonus (HintEvery = 0), and the once-only verified group reward grants 1 hint. Existing hint inventories and claim history are preserved; the lower grants apply only to future rewards. Level requirements are doubled to 1000 + 200 * (L - 1); saved level/XP, existing hint balances, mode unlocks, paid packs, tutorial hints and milestone gifts are preserved. The 500-entry dictionary and formula beyond 500 share the doubled curve. Old cumulative-XP migrations resolve the historical curve before preserving their level and within-level XP. Schema 19 remains unchanged. Migration never grants retroactive level rewards. Corrupt/future records cannot become writable defaults; saves still check the session token and retain receipt retry protection. Snapshot revisions are now session-only, while saveRevision/sessionToken/lastSavedAt remain server-only saved metadata.

Game.LevelBar is simplified to Star, XP and FillBar.Fill. Reward-preview children are optional and hidden on Game; existing fill and level-up effects remain active.

The client snapshot follows the compact structure with a session meta.snapshotVersion and derived XP preview fields. It excludes persistence/receipt IDs. All live Queue/Duel/reward/shop/settings/hint readers use the new fields. Data.Hints is an IntValue; Data.Progression mirrors Level/Xp/Solves/WordsFound and a Duel folder. Old Progress/Stats/Activity/TimedRewards mirrors are removed. Stats UI only displays Level, Solves, Hints and Duel results. Daily reward responses use streak. The playtime schedule/server loop/claim remote and client Rewards module are removed. Authored TimedRewards remnants are hidden.

Local compilation and pure/mocked tests cover source contracts, queue/round transitions, path authority, idempotent XP, hints, board dimensions/positions, finder rendering, profile normalization, tutorial state transitions, isolated practice validation, typewriter cancellation and spotlight geometry. EnvironmentTests executes both bootstrap safety paths, characterless UI mounting, existing-screen reuse and late root anchoring, and simulates three full daylight loops and camera lifecycle/replication edge cases; real cloud rendering, sun movement, replication smoothness and streaming still require a Studio session. Mocked GUI tests are not rendered Studio tests. Authored hierarchy, layout at real viewport sizes, live thumbnail loading, multiplayer remote timing, DataStore/receipt failures and published behavior require Studio/service validation.


The compact schema retains account.favouritePrompted (default false), mirrored as Player.Data.Account.FavouritePrompted and included in profile snapshots. FavouriteService waits 15 minutes from join and for a loaded profile/ready client, saves the once-only flag, then Social.FavouritePrompt opens the native Roblox favourite prompt. Failed saves retry after 30 seconds; leaving/shutdown cancels pending dispatch. Dismissal or a platform failure still consumes the attempt. Existing XP, receipts and tutorial history stay intact. See [PLAYER_DATA.md](PLAYER_DATA.md) for the exact saved defaults, runtime additions, Player folders and snapshot structure.

## Leaderboard refresh and presentation

SocialService reads the top 100 per category and merges the podium with trusted snapshots for currently loaded real players, sorts descending by total (ties by UserId within the returned entries), and publishes separate WordsFound / 1v1Wins / Level packets. QueueService publishes validated word totals; DuelService publishes accepted words and final win/loss snapshots. Bots and unready profiles never enter the indexes. Pending totals flush every 60 seconds, on leaving and on shutdown. UpdateAsync keeps the maximum stored lifetime total; failed writes retain newer pending values and retry even after the player leaves. Every 300 seconds the server flushes pending totals and refreshes all three global caches. Failed reads retain prior results and their last successful timestamp. Identity lookups reuse successful names/headshots for ten minutes.

Retained Remotes.Events.LeaderboardUpdateSolves now sends `(category, entries, updatedAt, revision, personal)`. Entries have UserId, Username, Thumbnail, Score and Rank. RequestLeaderboardUpdateSolves takes no arguments, is throttled per player to once per second, and returns all three categories from cache without triggering a DataStore query. Revisions are per category; the client rejects older packets and preserves the selected tab. A missing cached headshot uses an rbxthumb AvatarHeadShot URI for the ranked account, so no delayed script callback can repaint a reordered slot. Empty slots clear old images and values. Each panel uses its authored One/Two/Three instances, not cloned queue cards; panel/card geometry and the shared outer-modal transition remain unchanged. Local LeaderboardTests cover global/live merging, separate totals, failure retention, concurrent/departed writes, request throttling and scheduled refresh. BoardTests cover authored slots, medal colors, exclusive tab visibility, stale updates and the direct Leaderboards.Quit from all three tabs; these mocks do not prove Studio rendering or live DataStore availability.

## Daily rewards modal and timer

ProgressionController prefers Frames.DailyRewards and resolves Requirements.Title, Claim.TextLabel, Timer and Quit by exact path. The existing RewardService daily reward remains once per UTC day, resetting at midnight; each claim now grants 1 hint with no streak bonus; saved dailyReward history is preserved. Timer has no explanatory prefix or rich text. Claimable is 00:00 in RGB (75,170,95); waiting counts down in RGB (202,100,100), using HH:MM:SS above an hour and MM:SS below it. Unloaded state is --:-- in waiting red with Claim disabled. Requirements.Title receives the streak and reward description; the authored screen Title stays intact.

The client computes remaining seconds from a monotonic deadline established from the server's secondsUntilReset, instead of subtracting one second per timer wake-up. The one-second loop updates both open/hidden modal state and the Home availability badge. At reset it requests authoritative availability; failed checks retry at ten-second intervals without granting local claimability. Claim stays disabled when waiting or in flight, sends only the existing ClaimDailyReward request, applies returned snapshots and adopts authoritative state even for an already-claimed rejection. Revision and controller-lifetime guards reject older reads and callbacks after teardown. Clicking Claim while waiting cannot dismiss the frame; Quit uses the shared outer-modal close. BoardTests cover exact paths, color/format, elapsed-time countdown, automatic reset, double-clicks, failed claims, rejected duplicates, stale responses and retry backoff. ProfileTests retain the once-per-day server grant checks.

## Dedicated Duel lobby

Duels now uses Main.Frames.DuelLobby with Container.ScrollingFrame, its existing UIListLayout, and outer Quit/Title. It resolves 1v1Template from lowercase ReplicatedStorage.assets first, then the existing Assets folder; missing templates report a warning and never generate blank replacement rows. The old CustomFrame/DuelList/DuelSample path is no longer used by this feature. Home opens the standard 0.55 modal with the shared Main.Frames backdrop. AutomaticCanvasSize.Y fits cloned rows while preserving authored row geometry and list padding.

Server GetDuelPlayerList supplies usernames, user IDs and busy/pending states; unloaded profiles are unavailable alongside queued/tutorial/Duel players. Client rows exclude self, undeclared nonpositive IDs and duplicates, and are keyed by server identity. Declared bots use reserved negative IDs and verified supplied headshots. Opening begins a fresh portrait palette/row session. The four-second visible-lobby refresh and player join/leave refreshes reuse existing rows and colors, update names/availability, and remove departed rows. Each Mugshot uses the same shuffled 30-color palette as queue cards and a UIStroke blended 30% toward black (create a 2px mugshot stroke only if missing). Account headshot URIs avoid asynchronous repaint races. The source template, row border and Request content remain authored.

Only the direct Request button sends the current row's user ID and Duel mode through the existing challenge remote. Busy/pending targets, local in-flight invitations and target cooldowns disable it and are checked again by the click handler; the server retains final eligibility authority. Received challenges and results keep their dedicated request/outcome modals. Countdown hides DuelLobby. Closing stops list fetches; failed reads keep the last roster, concurrent list requests are suppressed, and teardown invalidates outstanding responses. Local BoardTests cover hierarchy, scrolling, template reuse, colors/strokes, roster changes, Request identity/guards, Quit/backdrop and stale requests. DuelTests cover unready profile presentation. These mocks do not prove authored Studio rendering or live multi-client timing.

## Incoming 1v1 invitation preference

Schema 19 adds settings.DuelInvites = true in WordHuntQueueData_v1. Normalization defaults only missing/invalid non-false values to On, preserves false, and leaves all other migrated profile fields intact. DataService snapshots copy the preference and Data.Settings.DuelInvites mirrors it as a BoolValue. The existing UpdateSetting endpoint saves the boolean; ServerBootstrap then calls DuelService.OnInviteSettingChanged. Settings.Frame.1v1.Toggle uses the same On/Off TextLabel, background, stroke and hover-safe color behavior as Music/SFX, while its stable saved key is DuelInvites.

The server's player-list duelRequestsEnabled flag reflects the saved preference; lobby Request controls respect that flag. SendChallenge rejects disabled recipients and RespondToChallenge rechecks the preference before starting. Board generation also rechecks the recipient after its yielding work. Turning Off cancels an existing incoming invitation and notifies both clients, but never abandons an active match or blocks initiating outgoing invitations. Expiry callbacks match the original pending record so cancelling, opting back in and receiving a replacement invite cannot let the older timeout expire the replacement. The client cannot bypass the saved setting by submitting an invite directly. ProfileTests cover migration, mirrors and persisted Off; BoardTests cover the exact 1v1 hierarchy/colors and disabled opponent rows; DuelTests cover send/accept/cancellation, active-match preservation and replacement timeout protection.

### Duel bot opponents

DuelBots tapers its random companion target by total real players: 1 player gets 2-6 bots; 2 gets 2-3; 3-4 get 1-2; 5-7 get 0-1; 8+ get none. The target rerolls every 60-120 seconds and when population changes. DuelService caps the entire displayed list at eight opponents, with real players first. Existing active/rematch bots remain reserved even when no longer listed. Verified portraits, session records and the 30-colour palette remain intact.

Request starts a server-owned Duel against that bot through the normal countdown, canonical board, progress and outcome flow. Bot portraits follow into the Duel HUD and word finder rows. DuelBots reuses QueueBots adaptive pacing with Duel-only tuning: 60% of opponents can lead by one word; followers lag by 0-1 words. Challenger pace multipliers are 0.65-0.85, followers 0.85-1.15, and first attempts become due after 14-26 seconds. Existing minimum delays, thinking pauses and progress caps remain: a stalled human prevents a board-clearing rush, and a challenger cannot finish before the human reaches the final word. Classic tuning is unchanged. Only a human's validated words and outcome affect their saved progression; bots never have Player instances, profiles or rewards.

Opponents are reserved before board generation and cannot enter two matches. Real-player arrivals replace spare list seats without cancelling active bot matches. Completion, abandon, departure and shutdown clean up the match/pool. Existing human challenge settings, cooldowns and busy gates remain enforced. The list refreshes every four seconds while open; server bot steps run once per second. This is repository source and mock-tested behavior, not Studio or published-place validation.

Bot portrait validation rejects account 36149989 and thumbnail URLs containing that account ID even when Roblox reports them ready, along with empty/whitespace or unready images. Both Standard/private queue and Duel pools use QueueBots.IsUsableAvatar before assigning or caching a portrait. Rejected results retry another account; fallback caches contain only accepted portraits, and bots stay unlisted until an image is accepted. Client portrait assignment also rejects the known blank URL. Thumbnail readiness cannot detect every visually blank asset or guarantee a client download during a Roblox service outage.

Hint/music feedback: profile updates no longer call Play on an already playing music track, so spending a hint cannot rewind/restart the music. Settings still mute at zero and restore volume 0.2, and stopped playback can resume. Unsatisfied Strands hint tiles and links pulse together between white and gold with a reversing 0.85-second Sine tween until the word is successfully dragged in either direction. Active selection stays grey and confirmed words take their permanent color. Refreshes preserve the current pulse phase; cancellation restores white tile faces. Legacy straight-path fixtures retain their transparency pulse. Solving the word, hiding Game, rebuilding the board or destroying its line cancels the pulse. Input selection thickness and rounded caps are 15% smaller; found/hint stroke geometry and cell hit-testing are unchanged. Local mocks verify playback position/call counts and pulse lifecycle; live frame timing/audio still require Studio observation.

Duel win-rate presentation uses existing saved progression.duel.wins/losses for real players, with no schema change. Each new bot receives a stable simulated history of 12-240 matches with a sampled 25-85% win share (rounded to whole wins); subsequent actual server-session Duel results, including forfeits, increment that record. No Player profile or DataStore record is created. Countdown and result packets send myDuelStats/opponentDuelStats to show `round(100 * wins / (wins + losses))% Win Rate` in Game.OneVsOneMode.YouWinRate/EnemyWinRate; no matches displays 0%. Results refresh both labels even if they arrive during entry. Duel list entries also carry their record, and an optional authored WinRate label is bound when present; no label is fabricated. Bot retirement/server shutdown discards that simulated identity's record.

Legacy optional Shop.Bulb and Shop.HintsOwned bindings apply only if an older Shop exists. Shop refreshes and profile updates set both to RGB (3, 36, 66) at transparency 0.5 when hints are zero, or RGB (43, 225, 58) at transparency 0 when at least one hint is owned. Bulb uses ImageColor3/ImageTransparency; HintsOwned uses TextColor3/TextTransparency. Preserve the authored image, label text and geometry.

Main.Game.TimedMode stays visible throughout every game mode and practice. It binds only the direct TimeLeft label, preserving Icon, UIAspectRatioConstraint, UICorner and UIStroke. TimedMode has no progress bar. The HUD derives remaining time from the server deadline; input locks immediately at zero. InterfaceController.UpdateTimedTimer formats MM:SS, with updates at most five times per second. Zero shows 00:00; missing timing shows --:--. Duel countdown shows the full allowance before its active deadline arrives. Completed results freeze at the server-recorded elapsed duration. Timed remains a retained definition without its own launcher.

Game.Hint uses SizeItUp-style occasional rotation: first cue after 3.5-5.5 seconds, then every 8-13 seconds, a 0.72-second damped four-swing wobble of up to 6.5 degrees. The existing HUD loop steps it; input locks, dragging, completion, hidden views and transitions cancel it and restore authored rotation. It does not take ownership of UIScale, so hover/press and screen transitions retain their normal size effects.

Duel lobby recovery: the client rediscovers late-replicating Duel remotes during its four-second refresh loop and when opening without the list remote. Event binding is idempotent, including lobby/player listeners; teardown resets the binding guards. Request stays unavailable until send/match remotes exist. Rate-limited server list requests reuse the last roster instead of returning an empty array; departure clears that cache. Duel avatar workers try four random accounts, then a verified cached image; with an empty cache they try connected real accounts before retrying. The blank-headshot block and readiness validation apply to every lookup, and callbacks stop after removal/shutdown. Standard avatar behavior and the random Duel population range are unchanged.

### Duel rematches and score feedback

DuelOutcome includes direct Rematch.TextLabel and Home buttons. A completed match offers Rematch (0/2); RequestDuelRematch accepts the exact finished match ID and one vote per participant. DuelMatch action rematch broadcasts availability and count. Both votes show 2/2 for 0.5 seconds, then a fresh server-owned puzzle/countdown uses the existing direct game entry fade with reset words, hints and scores. Bots accept after a varied 0.8-2.2-second delay and retain their identity/record while the result remains open. The normal six-second result cleanup releases human busy flags but preserves the rematch offer and reserves its bot. Home/abandon, departure, another activity or shutdown cancels the offer and any delayed restart; rematches grant no extra XP or outcome rewards. Admission is guarded across yielding generation.

Available Rematch keeps Home at scaled Position (0.764, 0.873); unavailable Rematch is hidden and Home is centered at (0.5, 0.873). Rematch joins the final outcome button pop-in stage. Late offer updates cannot reopen an old result. Game.OneVsOneMode.YouScore and EnemyScore flash green, grow to 1.18 times their authored scale and tilt five degrees on changed scores, then restore authored styling. Duplicate values do not retrigger; new boards cancel pending effects.

Classic bot population still randomly targets 2 through available seats, rerolling on population changes or every 60-120 seconds. New bots first become due after a varied 2-6 seconds. Subsequent admission gaps use a wider random factor (0.25-1.65), bounded by remaining countdown budget with a 0.45-second minimum; only one bot can join per scheduler step, with no catch-up burst.

Failed exit saves remain cached in DataService.pendingReleases. ReleasePlayer makes one immediate attempt, then retries after 2, 4, 8, 16 and at most 30 seconds between attempts while the server runs. SaveAll includes these departed profiles for autosave and shutdown. Successful saves clear the cache; a confirmed newer session stops retries without overwriting it. Duplicate release calls do not start additional workers, and same-server rejoining adopts the retained profile and invalidates the old worker. Deferred saves skip mirrors on departed Player instances. No schema, datastore namespace or cross-server ownership-claim changes. Server termination still limits how long an unavailable DataStore can be retried.

Duel lobby Request buttons are visible by default and hidden only when that opponent explicitly has 1v1 invites Off. Busy games/queues/tutorial/Duel admission, pending invitations, local cooldowns and unavailable remotes keep Request visible but inactive and unselectable until canRequest permits the challenge. Server roster busy state includes DuelBusy during yielding admission, and both the click guard and server challenge validation remain authoritative if a displayed roster becomes stale.

Tutorial.ReplayEveryJoin remains false. Tutorial.ReplayUserId = 1790165114 sets session-only TutorialReplayPending for the owner on every join, including recovery of a pending exit save. Skip/completion ends replay for that join without erasing saved history; all other accounts retain normal first-time/incomplete onboarding.

Unlocked Mini/Jumbo/Hardcore Play.TextLabel (Textlabel alias accepted) uses white text. Tutorial skips the other-player explanation and never inserts a demo portrait. Main.Queue.Solo calls StartSolo with mode Standard and enters Game through the existing single fade. Server generation succeeds before detaching the waiting player; failed generation preserves their queue. The resulting Strands board uses the saved-solves dimensions and is solo with no bots; Round snapshots carry solo=true, replay stays solo, and BoardController omits finder portraits in all solo modes and tutorial practice. Normal multiplayer finder portraits remain enabled. Solo uses the Standard timer; no additional solo rewards or persisted schema changes.

Outcome Words keeps its count-up, then ends at X/X Words in MM:SS. Above 1800 seconds it ends at X/X Words: Scenic route! (four space-separated words). QueueService records elapsed time from round creation through the accepted completion on each human member; queue waiting is excluded and entry animation is included. Duration is frozen per finisher in the round snapshot and forwarded to GameOutcome. DuelOutcome uses the existing server match duration (from active start, excluding countdown). Interface.OutcomeWords formats both animated and static result paths. Elapsed outcomes use the configured round limits; speed affects round score only, with no persisted schema changes.

Tutorial starts directly in Main.Game after GroupIntro and profile readiness, automatically requesting private 3x3 practice. The sequence is Loading -> FindCat -> TryHint -> FindDog -> FindFox -> Win -> HomeCongrats. Word descriptions are exactly `Make CAT!`, `Make DOG!` and `Make FOX!`; both traversal directions remain accepted. A passive `TutorialDragGuide` ImageLabel using `rbxassetid://130798161958633` loops smoothly along the current canonical word path, with a short fade and pause between demonstrations. It follows current grid geometry, hides while typing, transitioning, entering the board, dragging or awaiting a request, and is removed on step changes/Skip/Close. It never simulates input or submits words. Failed Start requests retry in Game at two-second intervals; timed-out practice also restarts directly in Game. Word and hint steps wait for player actions. Win keeps its 32-piece confetti shower, normal animated Home return and final Tutorial done message. Practice remains solo, with no finder portraits, real queue, XP, statistics or inventory spending. Completion/Skip persistence and owner-only replay remain intact.

All Frames modals open to UDim2.fromScale(0.33, 0.33) through the shared modal controller. GameOutcome exposes only Play and Home outcome actions; there is no Quit handler.

Current beginner Strands policy (2026-09-24): Standard uses a 5x5 beginner board below ten saved solves and a 7x7 board afterward (columns x rows). BuildClassicDefinition applies this to private queues and solo/replay admission from authoritative saved solves. Every cell belongs to one hidden theme word or the spangram; word counts vary with the exact-cover selection. No skill averaging, filler letters or overlapping answers remain.

Leaderboards.You is a direct child alongside WordsFound, 1v1Wins and Level, with Mugshot, Username, Data and Place. It always shows the local account and the selected category's lifetime total, refreshed from the profile. Place uses the server personal payload only when its Score matches the displayed total; otherwise it shows -- until a matching update. The existing five-minute leaderboard refresh reads 100 entries per category in one GetSortedAsync call (no extra calls, pagination or per-player rank scans). Only the displayed top-20 identities are fetched and cached. Personal ranks merge that cache with trusted live totals and use numeric UserId to break ties. An exact #N is shown when the cached range establishes it; scores below a full page's cutoff show 100+, and cutoff ties, zero or unavailable data show --. Failed reads retain the previous cache/timestamp. This is cached ranking, not instantaneous cross-server placement. Opening/switching tabs makes no sorted DataStore queries; no index backfill or profile schema changes.

Leaderboard tabs now use direct Container ScrollingFrames with authored UIListLayout. ProgressionController clones ReplicatedStorage.Assets.LeaderboardTemplate for up to twenty available entries, reuses rows by rank and removes only stale LeaderboardRank rows. Preserve all containers' authored Bottom padding frames, including their size/visibility; keep Bottom.LayoutOrder at least 21 so padding follows all twenty entries. Each row binds Mugshot, Data, Place and Username; ranks 1-3 use medal colors and 4-20 preserve template styling. You remains separate and follows the active tab. SocialService publishes twenty entries per category; one top-100 cache read per category every 300 seconds still supports personal rank bounds. Writes remain every 60 seconds; opening or switching tabs never triggers sorted-store reads.

Duel lobby population policy (2026-09-07): eight displayed opponents maximum, real players first. Six real players see their five real opponents and at most one bot. Random bot limits apply in both refresh and simulation ticks and when serializing the list. Classic queue bot counts are unaffected.

The optional legacy Shop.HintsOwned.Text binding shows the current nonnegative integer hint count (for example 0 or 30), refreshed with shop/profile state alongside its existing empty/available styling. TutorialSpotlight overscan extends 0.75 viewport widths/heights beyond each edge, 50% farther than the prior 0.5 margins: root Position (-0.75,-0.75), Size (2.5,2.5). Layout derives the original viewport from this factor so highlight alignment and prompt placement stay unchanged. Mobile edge coverage still needs visual verification in Studio.

Frames.Leaderboards.Level is the third authored leaderboard panel alongside WordsFound and 1v1Wins. Its Level tab selects the saved XP progression.level ranking, independently of per-round score levels. All three panels use their authored Container/UIListLayout and Assets.LeaderboardTemplate for up to twenty rows (legacy One/Two/Three slots remain supported), preserve Bottom padding, share medal styling and the outer Quit, and stay mutually exclusive. WordsFound remains the default; updates preserve the selected tab. The shared You row shows the selected statistic and only a matching cached personal rank. SocialService reuses WordHuntQueueLevels_v1 through GameConfig.Meta.LEADERBOARD.LevelStoreName, preserving existing records and adding loaded players from authoritative snapshots. Level uses the same 60-second write queue, 300-second top-100 cache refresh, top-20 publication, tie ordering, trusted profile values, request throttling and failed-read/write recovery as the other categories. Bots and unready players are excluded. No profile reset, offline backfill or new profile fields are introduced.

Game.TimedMode uses Position (0.5, 0, 0.03, 0) during Duel/1v1, including countdown and rematches. BoardController captures its authored Position once before any board entry, then restores that exact UDim2 (including offsets) for Standard, Mini, Jumbo, Hardcore, Timed and tutorial practice. TimedMode remains visible and existing entry/exit animations use the selected mode position.

Invalid Strands selections flash every attempted tile red with readable white letters and red connections. A single passive WrongWordFeedback snapshot shakes and fades the entire path together (0.22-second feedback, 0.18-second fade, removal at 0.42 seconds), without changing real tile colors, solved words or hint pulses. Starting the next mouse/touch/keyboard/gamepad selection cancels that snapshot immediately; rebuilding or destroying the board cancels its tweens and pending callbacks. Error2 and existing server validation/Hardcore behavior are unchanged.

Word orientation favors left-to-right or top-to-bottom reading along each path's dominant start-to-end axis. After splitting the covering path, StrandsGenerator independently gives each word a 5% chance of reverse orientation on beginner Standard and Mini boards, or 15% on all other generated modes. Ties use the horizontal axis. Reversing a word's cell order happens before lettering and preserves adjacency, bends, complete coverage and spanning; word selection, rewards and dimensions are unchanged. Fixed CAT/DOG/FOX tutorial placement is unchanged. Players can still solve every answer in either direction. Probabilities apply to newly generated boards, not existing canonical rounds. ModeTests checks observed orientation rates across the existing 2,076 seeded boards alongside spelling, coverage and reverse-validation checks.

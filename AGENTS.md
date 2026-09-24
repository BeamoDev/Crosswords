# Crosswords agent handoff

Applies to this repository. Reconciled against source on **2026-09-25**.

## Start here

- Read README.md and ARCHITECTURE.md before edits; inspect the current implementation. Keep those files and this handoff synchronized when behavior, hierarchy or ownership changes. PLAYER_DATA.md documents saved data.
- This folder was cloned from WordPath/Strands. The active game is now a **typed crossword**, using the newer queue/solo/Duel/progression systems. Old notes about dragging, spangrams, exact letter coverage, bonus dictionary words, sequential campaigns and Desktop/Mobile HUD cloning are obsolete.
- Work on `src/`. Do not sync Studio or publish a Roblox place unless explicitly requested. Source/mock results do not establish what runs in Studio. Git commit/push also requires a user request.
- Preserve unrelated checkout work. Never reset the checkout, restore removed gameplay modules from history, or overwrite user changes. The conversion retains removed originals in ignored `.local-backup/`; never commit or synchronize that directory.
- There is no Rojo/Wally/Rokit project manifest. Do not introduce deployment tooling or generated places as a side effect.
- Keep one ClientBootstrap LocalScript and one ServerBootstrap Script. Preserve GameController's StarterPlayerScripts descendant guard. Do not infer new live script placement.
- Preserve lowercase `ReplicatedStorage.shared`, including the UIEffects path required by authored `Main.FX`.

## Crossword authority

- `src/server/puzzle/PuzzleGenerator.luau` owns mode definitions and canonical assembly. `CrosswordLayout.luau` implements bounded seeded placement adapted from OLDSRC. `src/server/content/CrosswordBank.luau` holds 986 unique original word/clue records. These folders are siblings of server services/data/systems and must remain **server-only**.
- Do not bring back the old OLDSRC bootstraps, UI, progression, shops, stores or campaign. Their useful generator/data were extracted; old source is archived locally, outside active source.
- Standard below ten saved solves: 5 Easy clues, max 9x9. Standard graduates: 7 mixed, max 11x11. Mini: 4 Easy, max 7x7. Jumbo: 12 mixed, max 15x15. Hardcore: 8 mixed, max 11x11. Duel and retained Timed definition: 7 mixed, max 11x11. Crop the actual grid to occupied bounds; blocks are expected.
- All entries are straight, forward Across/Down, connected through equal crossing letters. Never create overlapping same-direction entries, touching endpoints, parallel side runs or unclued multi-letter runs. IDs are number + A/D; a shared start shares its number. Generation must reach the requested clue count or fail cleanly.
- Canonical puzzle `words` is an array of **entry IDs**, not answer strings. `placedWordsByWord[id]` contains clue, direction, number, length, path and private answer. Use `entry.length` / `entry.answer` for XP and score, never `#id`.
- Shared PuzzleEngine.PublicPuzzle builds a whitelist projection: clue metadata, IDs/paths, and a mask (`""` block, `" "` open). It excludes answers and seeds. Never send canonical puzzles or the answer bank to clients.
- Queue/Tutorial Word payloads are `{action="Word", roundId, word=<id>, answer=<text>}`; Duel progress also requires the current `matchId`. Old drag paths, score/XP claims and found-word claims cannot validate an answer. Check member/match identity, active state, deadline, bounded payload, ID, alphabetic answer length and exact case-normalized spelling.
- A hint reveals an entire unsolved answer and its shared letters. It does not confirm the clue. Round snapshots include `revealedAnswers` only on the recipient's own member record; Duel uses `myRevealedAnswers` and hint boardState.revealedAnswers. Other players' solves/hints must never disclose their answers. Keep broadcasts recipient-specific.
- Completion requires each entry to be explicitly confirmed. Duplicates, late packets and malformed/incomplete attempts cannot award anything. Hardcore loses only after Check submits a known entry with a full-length incorrect alphabetic answer. There are no bonus dictionary words, spangrams or path claims.

## Editing and authored UI

- BoardController generates crossword cells/blocks, CurrentClue and CrosswordKeyboard inside the existing square `Main.Game.BOARDINFO` (BoardInfo / legacy BoardPanel aliases). Preserve the panel Position, Size, AnchorPoint and authored decoration. Do not generate replacement screens.
- White playable squares have clue numbers and blank letters initially; black squares are passive. Use Ubuntu Bold. The grid fits above the keyboard with square cells even for rectangular crosswords.
- CrosswordInput is the pure local editing owner. Cell drafts are shared by intersecting entries. Confirmed/hinted letters are locked; local edits cannot change them. Retain unrelated drafts on progress updates, reset on new boards, preserve through pause. No local guess can set foundWords or score.
- Click/tap clues or squares to select. Repeated crossing activation switches direction. Type letters, arrows move, Space switches direction, Backspace erases, Tab/Next and Prev change clues, Enter/Check submits. Never auto-submit merely because an entry is full, particularly in Hardcore.
- On-screen QWERTY supports touch and controller; the manually tapped Type answer TextBox supports the native device keyboard. Typing the whole entry preserves crossing locks. No programmatic CaptureFocus/ReleaseFocus, GuiService.Select or writes to GuiService.SelectedObject. Reading selection to respect user navigation is allowed.
- Keep GuiButton.Activated for pointer/touch/controller actions. Gamepad supports native navigation, shoulder clue changes, X direction switch and B pause. Locks apply during modals, transitions, pending calls, tutorial reading, hidden Game, expiry and completion.
- Clues clone `Assets.WordPanelTemplate` into WordPanel.Container.ScrollingFrame. Show number, Across/Down, definition and answer length; wrap within a readable region. Keep stable Across then Down ordering, BreakLine, FoundPanel and no strike-through. Clicking a clue selects its cells.
- WordPanel.Words shows only local found/total (e.g. 2/7). Opponent finds add portraits, never fill local squares or complete local entries. First three chronological finders use foundOrder; overflow clones `Assets.Exceeds.TextLabel` as +N. Departure promotes the next finder. Solo/practice omit portraits.
- Portrait palettes/headshots remain stable per round/card. Keep the shuffled 30-colour palette (saturation 0.75-0.85, value 0.85-0.95), darker matching stroke, verified bot image and stale-thumbnail guards. Hide optional authored Profile placeholders.
- Main.Game Title/Subtitle/Exit are optional. Do not create replacements. Keep authored Background and Streak. Timer is always visible; Game.TimedMode moves to (0.5,0.03) for Duel and restores its exact authored position otherwise.
- Game.Score.Score shows Score: X. Score.Level.Label (lowercase alias allowed) shows crown + Level N. Reset each board, including practice/rematches. Level = 1 + floor(score/500); bronze 1-5, silver 6-10, gold 11-15, diamond 16+. Only changed authoritative levels pulse. No replacement Score frame.
- Preserve Home, Queue, GroupIntro, Frames modals, white transitions, XP bars, existing pause/Leave and result Play/Home/Rematch. Input locks last through reveals; late callbacks cannot reopen an old round. The removed Home Shop and Frames.Shop remain optional; empty Hint prompts existing product 3714523709.
- Home Standard/Mini previews sweep straight Across/Down entries (5 / 3 cells), preserving colour/timing/cancellation. Jumbo's decorative 3x3/6x6 morph remains independent of gameplay size. Keep Pattern/GameIcon/waiting animation contracts and authored scales.
- Standard `.Play` always uses `BackgroundTransparency = 0.2`. When Mini, Jumbo or Hardcore is unlocked, its `.Play` GuiObject uses `BackgroundTransparency = 0.7`; the locked state keeps its authored background appearance.

## Queue, Duel and timers

- ?Classic? in older compatibility method names means Standard; no Classic generator mode is supported. Unlock authority remains ProgressionConfig.Experience.ModeLevels: Mini 5, Jumbo 10, Hardcore 20. Do not hardcode a second set.
- First waiting member starts the 15-second deadline. Duplicate/later joins do not extend it. Empty queues cancel; expiry detaches one canonical cohort while new arrivals form another. One human still starts normally. Two players do not automatically become a Duel.
- Below ten saved solves, use private QueueState/QueueBots ownership. Graduates share public waiting. Private/public publication revisions share one monotonically increasing stream per server. Never leak another beginner roster.
- Queue.Solo uses Standard saved-solves policy, no bots, and immediate entry. Preserve queued membership if generation fails. Exiting affects only that member; dispose after the last real member. Gates ProfileReady/RoundBusy/DuelBusy/TutorialBusy prevent overlap.
- Preserve Standard bot capacity (public target 2 through available seats out of 12), independent beginner companions, verified headshots, blank-account rejection, randomized staggered admission, adaptive human pacing/challenger caps and no burst catch-up. Bots use canonical answers through round validation, never profiles or rewards. Active bot ownership must survive population changes and old-round exits.
- Duel retains human challenges, invite preferences, cooldowns, private bot pool, maximum eight lobby entries, existing countdown/race/results and mutual rematch votes. Entry count determines the winner. Rematches use fresh puzzles and reset score/drafts, retaining opponent identity. Match IDs reject stale submissions. Throttle incorrect attempts too.
- GameConfig.RoundSeconds is sole timer authority: Standard/Hardcore/Duel/practice 180, Mini 90, Jumbo 300. Queue waiting is excluded; normal entry animation is included. Duel starts after countdown. Pause/modals do not stop time.
- Timeout preserves partial earned XP and grants no completion bonus. Duel ties draw. Completed members freeze results/remaining time. Expired practice retries without completing onboarding. Do not add timer products/extensions/freezes.

## Progression and persistence

- DataService alone owns compact schema 19, session ownership, serialized saves, mirrors, snapshots, pending exit-save retries and shutdown. Keep WordHuntQueueData_v1 / player_<UserId> and existing leaderboard namespaces. This conversion makes no production reset/migration.
- Every accepted human answer awards 20 XP per answer letter and increments lifetime Words Found once. Completion adds 120 XP and existing mode rewards. Practice/bots/hints/duplicates do not increment real counters. Crossings count in each confirmed entry.
- Session score is 100 points per answer letter, or 50 if explicitly hinted, plus floor(1000 * remaining/timeLimit) once on successful completion, bounded 0-1000. No bonus for partial expiry/loss/forfeit. Score is independent of saved XP, inventories and Duel count-based victory.
- Fresh Level 1/zero XP; leaving Level L needs 1000 + 200*(L-1). Keep immutable 500-level config and formula beyond it. Each newly crossed even level grants one hint. Daily and once-only verified group reward each grant one hint. Existing inventories/receipt history remain intact.
- Preserve paid-receipt idempotency, retryability and save-before-PurchaseGranted; unknown products stay NotProcessedYet. No credential/webhook URLs in source. Private purchase webhook configuration stays server-private.
- Keep Words Found / 1v1 Wins / Level leaderboards, cached top-100 reads every 300 seconds, top-20 publication and 60-second write batching. Opening tabs does not query stores. Preserve authored Bottom padding and You personal row, tie/rank semantics and failed-read cache retention.
- Preserve Music/SFX/DuelInvites settings, Daily/group/gifts, favourite prompt and existing moderation-free meta flow. Do not restore popup alerts, timed rewards, admin tools, retired game modes or old stores.

## Tutorial, bootstraps and effects

- Practice is a connected 3x3 CAT Across / CAR Down / RED Across crossword, with two blocks and no real XP/inventory writes. Stages: Loading -> FirstAcross -> TryHint -> FirstDown -> LastAcross -> Win -> HomeCongrats. Teach typed answers and explicit Check; the entire board panel remains in the interaction opening for touch keys. No drag demonstration.
- ReplayEveryJoin remains false; retained owner ReplayUserId override is session-only. Skip/completion persists existing history, keeps late-response/callback guards and retryable saves. Timeout/failed Start retries stay in Game. Tutorial does not enter real queues or show example portraits.
- Keep authored Tutorial Content/Skip/Icon/PopScale, reading/transition locks, normal animated Home return, celebration and final congratulations. Skip releases interaction immediately. Never manipulate GUI focus.
- CharacterAutoLoads=false, one authored Main and GroupIntro on every device, ResetOnSpawn=false, early anchor fallback, fixed replicated CamPart/FOV40 and daytime sky remain. Music starts after intro and respects settings; hints must not restart playback.
- UIEffects remains at its existing shared path for authored FX. Preserve cancellation, authored scale/geometry restoration, modal backdrops and generation guards on delayed effects.

## Validation and deployment boundary

Run the full Lune suite after gameplay changes, then inspect imports, client/server contract agreement and `git diff --check`:

```powershell
foreach ($check in @('Compile','ModeTests','QueueTests','QueueServiceTests','BoardTests','ProfileTests','TutorialTests','LobbyTests','DuelTests','EnvironmentTests','FavouriteTests','LeaderboardTests')) {
    lune run "tests/$check.luau"
    if ($LASTEXITCODE -ne 0) { throw "Failed: $check" }
}
git -c core.safecrlf=false diff --check
```

If the Rokit shim fails, inspect `C:/Users/User/.rokit/tool-storage/lune-org/lune/0.10.2/lune.exe`; do not add a manifest merely to bypass a launcher issue.

ModeTests covers 841 generated boards, connected crossings, clue coverage, deterministic seeds, public redaction and editing. Keep service tests for admission, privacy, malformed/stale requests, Hardcore, hint spending, scoring, timeout, bots, Duel/rematches and tutorial; preserve meta/profile regression coverage. Tests are source and mocks, not live Roblox evidence.

Studio deployment must add server puzzle/content, remove retired shared generator/dictionary modules, retain existing authored assets and verify on phones/tablets/desktops/controllers. Specifically check clue readability, native/virtual keyboard, tutorial overlap, multi-client privacy, timers, receipts and replay/exit. Do not synchronize tests or local backups. Git push is not Studio synchronization or Roblox publishing.

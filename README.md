# Crosswords

A Roblox crossword game built on the existing shared-queue, solo and Duel game systems. Players select numbered Across/Down clues, type answers into a connected grid, and press Check. Crossing squares share letters. Black squares separate entries. The clue panel shows definitions and answer lengths, never a list of solutions.

This replaces the cloned WordPath/Strands gameplay. Queues, bots, progression, profiles, rewards, timers, portraits, transitions and authored screens remain in use.

## Play

- Click/tap a clue or white square. Tap a crossing again to switch Across/Down.
- Type A-Z or use the on-screen keyboard. Tap Type answer to use your device keyboard for a whole entry.
- Arrow keys move between cells; Space switches the crossing direction. Tab/Next advances to the next unsolved clue; Prev returns to the previous one.
- Backspace/Erase removes editable letters. Solved and hinted letters remain locked.
- Enter/Check submits the selected entry. Filling squares alone does not submit or complete it.
- Gamepad uses native button navigation and the on-screen keyboard; shoulder buttons change clues, X switches direction, B opens pause. No code assigns UI focus.
- Hint reveals one unsolved answer and its crossing letters. Press Check to confirm it. Practice hints are free; other hints use the existing inventory/purchase flow.

An incorrect Check can be corrected in regular modes. In Hardcore, a complete, incorrect answer ends the round; incomplete or malformed requests do not. All entries must be confirmed, even when crossings have filled their letters. There are no drag paths, spangrams or extra-dictionary-word rewards.

## Modes

Dimensions are maximum columns x rows. The generator crops to the connected crossword's bounds; playable cells and clue counts vary in shape, not in the requested number of entries.

| Mode | Access | Clues | Maximum grid | Time |
| --- | --- | --- | --- | --- |
| Standard, below 10 saved solves | Private 15-second companion queue | 5 easy | 9x9 | 180s |
| Standard, 10+ solves | Shared 15-second queue | 7 mixed | 11x11 | 180s |
| Mini | Level 5, immediate solo | 4 easy | 7x7 | 90s |
| Jumbo | Level 10, immediate solo | 12 mixed | 15x15 | 300s |
| Hardcore | Level 20, immediate solo | 8 mixed | 11x11 | 180s |
| Duel | Existing challenge / bot / rematch flow | 7 mixed | 11x11 | 180s after countdown |
| Tutorial | Private, no XP or inventory cost | CAT / CAR / RED | 3x3 | 180s |
| Timed | Retained definition; no launcher | 7 mixed | 11x11 | 180s |

Queue.Solo starts Standard immediately with the same saved-solves difficulty and no bots. Opponents share the same crossword but have independent answers. Their portraits mark confirmed clues without revealing or filling your solution. Duel races compare confirmed entry counts; timeout ties draw. Pause and modals do not stop time.

## Content and authority

The original `OLDSRC` supplied a bounded, deterministic crossword layout algorithm and **986 unique authored answer/clue pairs** extracted from its 320 puzzle records. The active versions are `src/server/puzzle/CrosswordLayout.luau` and `src/server/content/CrosswordBank.luau`. The older game's bootstraps, UI, shops, campaign and persistence modules are not active. Original source and removed dictionary files are retained only in ignored `.local-backup/` locally.

The answer bank and generator are server-only. Public puzzles contain numbered IDs (`1A`, `1D`), clues, lengths, cell paths and a blank/block mask. They omit solutions and generation seeds. Submissions contain an entry ID and typed answer, checked against the server's canonical puzzle and the current round/match. Only the recipient's own solved/hinted answers are returned. Unknown IDs, old path requests, duplicates and stale sessions cannot award XP or score.

Accepted answers earn the existing 20 XP per letter and 120 completion XP. Session score is 100 points per answer letter (50 if hinted), plus at most 1,000 points for remaining time on completion. Shared letters count once per confirmed entry. Session score and its crown level reset each board; saved XP levels, hints, lifetime Words Found and Duel records retain their existing owners and schema.

## Source and Studio setup

Read [ARCHITECTURE.md](ARCHITECTURE.md), [AGENTS.md](AGENTS.md), [PLAYER_DATA.md](PLAYER_DATA.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Keep the existing synchronized hierarchy: one client bootstrap, one server bootstrap, lowercase `ReplicatedStorage.shared`, the authored `StarterGui.Main` and `GroupIntro`, and existing Assets templates. Under the existing server source root, add the new sibling `puzzle/` and `content/` folders next to `services/`, `data/` and `systems/`. **Do not put the answer bank or generator in ReplicatedStorage.** Remove the retired shared generator/content modules from the synchronized place when deploying this conversion. Do not synchronize `.local-backup` or `tests`.

The authored `Main.Game.BOARDINFO` (BoardInfo/BoardPanel aliases) hosts generated cells, the current clue and touch keyboard. `WordPanel.Container.ScrollingFrame` hosts clue rows cloned from `Assets.WordPanelTemplate`. Title, Subtitle and Exit are optional. Existing Main, Home, Queue, modals, transitions and timer remain authored. There is no Rojo project or replacement place file.

Product IDs, group settings and datastore names still come from the existing configuration. Git publication does not reconfigure these assets for a different Roblox experience. DataStore names/schema were not reset or migrated as part of the gameplay conversion.

## Local validation

Run from this directory with Lune:

```powershell
foreach ($check in @('Compile','ModeTests','QueueTests','QueueServiceTests','BoardTests','ProfileTests','TutorialTests','LobbyTests','DuelTests','EnvironmentTests','FavouriteTests','LeaderboardTests')) {
    lune run "tests/$check.luau"
    if ($LASTEXITCODE -ne 0) { throw "Failed: $check" }
}
git -c core.safecrlf=false diff --check
```

ModeTests generates 841 crosswords and checks deterministic seeds, exact clue counts, connectivity, matching crossings, full clue coverage of every multi-letter run, dimensions, private answers, Hardcore rules and local editing. Service and UI mocks exercise queues/bots, hints, scoring, timers, tutorial, Duel/rematches, rewards, receipts, profiles and retained presentation.

These checks do not establish live Studio rendering or published-place behavior. Before a Roblox release, verify phone/tablet/desktop clue readability and keyboard size, controller navigation, tutorial positioning, multi-client privacy, receipts and the complete play/replay/exit flow in Studio. This repository update does not synchronize or publish a Roblox place.

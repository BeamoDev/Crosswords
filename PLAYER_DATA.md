# Player data: version 19

DataService owns the profile in `WordHuntQueueData_v1`, key `player_<UserId>`. Saves remain JSON strings in the existing store; no new namespace or production reset is performed. This describes repository source, not a production export.

Standard crossword onboarding reads the existing `progression.solves`: below 10 completed boards, Standard uses private five-clue beginner rounds; at 10 it opens shared seven-clue queues. Tutorial practice and unfinished boards do not increase it. Saved level owns Mini/Jumbo/Hardcore unlocks. The crossword conversion adds no saved fields or schema change. Entry IDs, typed drafts, revealed answers and round score are session-only.

## Exact saved defaults

```luau
{
    version = 19,
    progression = {
        level = 1,
        xp = 0, -- XP within the current level
        solves = 0, -- Completed boards, including Duel wins
        wordsFound = 0, -- Lifetime accepted word finds outside tutorial practice
        duel = { wins = 0, losses = 0 },
    },
    hints = 0,
    dailyReward = { lastClaimDay = -1, streak = 0 },
    dailyPuzzle = { day = -1, completed = false, foundWords = {} },

    puzzlePieces = 0,
    settings = { SFX = true, Music = true, DuelInvites = true },
    tutorial = { completed = false, skipped = false, completedAt = 0 },
    account = {
        favouritePrompted = false,
        groupRewardClaimed = false,
        giftClaimMilestone = 0,
        processedReceipts = {}, -- [purchaseId] = Unix timestamp; newest 150
    },
    persistence = { sessionToken = "", saveRevision = 0, lastSavedAt = 0 },
}
```

The additional fields support the existing piece shop, music/SFX/invite settings, tutorial, favourite prompt, group/gift rewards and paid receipt/session safety. They are not old statistics. The Level dictionary still has 500 entries and the same formula beyond 500; the profile stores no redundant totalXp or levelRewardsThrough. DataService computes cumulative XP only when adding XP, resolves the new level/xp pair, then grants the difference in level-up hint rewards. Migration itself grants no retroactive level rewards. Each newly reached even level (2, 4, 6, and so on) grants one hint; odd levels grant none. Daily claims grant 1 hint with no extra streak bonus (HintEvery = 0), and the once-only verified group reward grants 1 hint. Existing hint inventories and claim history are preserved; the lower grants apply only to future rewards. XP requirements, mode unlocks, paid packs, tutorial hints and milestone gifts are unchanged.

`dailyPuzzle` is prepared data only: no daily puzzle launcher, generator or client write remote was added. `foundWords` is a map such as `{ CAT = true }`, with at most 32 uppercase word keys of up to 32 letters. Only today's UTC day is retained; expired or future progress resets to the defaults. Daily login rewards remain a separate active feature. Daily stamps are UTC day numbers; completedAt, lastSavedAt and receipt values are Unix seconds.

## Migration and removed fields

Version 19 adds settings.DuelInvites, defaulting to true for new profiles and older records where it is missing. False survives normalization, snapshots, BoolValue mirrors, saves and rejoins. It controls incoming invitations only; existing matches are not abandoned. Existing progress, inventory, receipts and audio settings are preserved in the same profile store.

Version 18 adds progression.wordsFound, normalized to a nonnegative integer and initialized to zero when absent. It increments once per accepted canonical word in Standard (including private beginner rounds), Mini, Jumbo, Hardcore and Duel, even if the puzzle is later abandoned. Duplicate/invalid requests, hints alone, completion bonuses, bot finds and tutorial practice do not increment it. Existing counts survive normalization, snapshots, saves and rejoining; historical totals are not estimated from solves. This does not change Level leaderstats or the solves-based beginner admission gate.

Version 16 totalXp becomes level plus in-level xp. Earlier pre-13 constant-XP records retain their earned level and fractional progress on the existing increasing curve. Solves migrate from the larger of boardsCleared/Total wins; only Duel's wins/losses remain separately. Hints, pieces, daily claim/streak, tutorial history, claimed rewards and favourite/receipt flags survive. Pre-15 retired timer inventory still converts to hints once.

Normalization creates a strict whitelist and drops timedRewards, old resources/stats/activity, mode result/streak buckets, old dailyMode, retiredModes, saved board/star progress, best-streak/playtime/fastest-solve counters and unknown fields. Old records are upgraded when they load; the repository edit does not itself write production data. Corrupt records and future schema versions fail loading rather than becoming writable defaults.

Snapshot revisions are session-only. Save revision, session token and save time stay server-only in the persisted record. Save ownership checks, serialized writes, autosave and shutdown saves remain. Paid receipt retries remain idempotent and the server acknowledges a receipt only after saving its grant/ID.

## Player instances

```text
Player
  leaderstats
    Level                     IntValue (only leaderstat)
  Data
    Hints                     IntValue
    PuzzlePieces              IntValue
    Progression
      Level                   IntValue
      Xp                      IntValue
      Solves                  IntValue
      WordsFound              IntValue
      Duel
        Wins                  IntValue
        Losses                IntValue
    DailyReward
      LastClaimDay            IntValue
      Streak                  IntValue
    DailyPuzzle
      Day                     IntValue
      Completed               BoolValue
      FoundWords
        <word>                BoolValue (true)
    Settings
      SFX                     BoolValue
      Music                   BoolValue
      DuelInvites             BoolValue
    Tutorial
      Completed               BoolValue
      Skipped                 BoolValue
      CompletedAt             IntValue
    Account
      FavouritePrompted       BoolValue
      GroupRewardClaimed      BoolValue
      GiftClaimMilestone      IntValue
```

Mirrors never contain receipt IDs or persistence internals. Old Progress, Stats, Activity and TimedRewards folders are removed. Hints changes from a folder to one IntValue; all active readers use the new structure. Tutorial mirrors honor the session replay override while preserving saved history. ProfileReady, TutorialReplayPending, TutorialBusy, RoundBusy and DuelBusy remain session attributes.

## Client snapshot

GetBootstrap/StateUpdated send progression, hints, puzzlePieces, dailyReward, dailyPuzzle, tutorial, settings and account from this structure. The account snapshot excludes processedReceipts; persistence and saved version are omitted. The snapshot adds `meta.snapshotVersion` and derived progression fields `xpToNextLevel`, `nextLevel`, `nextLevelRewardHints`. Tutorial adds `replaying = true` while the session override is pending. Snapshot tables are copies, not server data references.

Queue/solo/Duel readers use the compact level, XP, hints and solves fields. Statistics presentation now shows Level, Solves, Hints, Duel Wins, Duel Losses and derived Duel Win Ratio. Daily reward responses/UI use `streak`, not a saved best streak. Timed reward tracking, schedule, claim remote and client feature module are removed; any leftover authored TimedRewards UI is hidden.

## Favourite prompt

After 900 seconds in the current server, FavouriteService requires a loaded profile and ready client, saves account.favouritePrompted, then dispatches Roblox's native favourite prompt. The mirrored BoolValue stays true across rejoins, including dismissal or prompt failure. Failed saves retry; departure/shutdown cancels pending dispatch. The flag records a consumed prompt attempt, not proof of a favourite. Saving first prioritizes preventing repeat prompts; disconnecting between save and display may consume the attempt without showing it.

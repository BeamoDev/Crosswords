-- Server-only generation. Public metadata is projected by PuzzleEngine.PublicPuzzle.
local Layout = if script then require(script.Parent.CrosswordLayout) else require("./CrosswordLayout")
local Bank = if script then require(script.Parent.Parent.content.CrosswordBank) else require("../content/CrosswordBank")
local Generator = { BeginnerSolves = 10 }
local modes = {
    Standard = {size=11, count=7}, Mini = {size=7, count=4},
    Jumbo = {size=15, count=12}, Hardcore = {size=11, count=8},
    Duel = {size=11, count=7}, Timed = {size=11, count=7},
}

function Generator.BuildDefinition(level, mode, seed)
    local config = assert(modes[mode], "Unsupported puzzle mode: " .. tostring(mode))
    return {level=level, mode=mode, rules="Crossword", seed=seed,
        gridSize=config.size, gridWidth=config.size, wordCount=config.count}
end

function Generator.BuildClassicDefinition(_members, seed, solves)
    local definition = Generator.BuildDefinition(1, "Standard", seed)
    definition.beginner = type(solves) == "number" and solves < Generator.BeginnerSolves
    if definition.beginner then
        definition.gridSize, definition.gridWidth, definition.wordCount = 9, 9, 5
    end
    return definition
end

function Generator.BuildTutorialDefinition(seed)
    return {level=1, mode="Standard", rules="Crossword", tutorial=true,
        seed=seed, gridSize=3, gridWidth=3, wordCount=3}
end

local function assemble(board, definition, seed)
    local puzzle = {rules="Crossword", title=board.title, subtitle=board.subtitle,
        tutorial=definition.tutorial, level=definition.level, mode=definition.mode, seed=seed,
        gridSize=board.rows, gridWidth=board.cols, letters={}, words={}, placedWordsByWord={}}
    for row = 1, board.rows do puzzle.letters[row] = table.create(board.cols, "") end
    for _, entry in ipairs(board.entries) do
        local id = tostring(entry.number) .. (entry.dir == "H" and "A" or "D")
        local placed = {id=id, number=entry.number, direction=entry.dir == "H" and "Across" or "Down",
            clue=entry.clue, length=#entry.word, answer=entry.word, path={}}
        for index = 1, #entry.word do
            local row = entry.row + 1 + (entry.dir == "V" and index - 1 or 0)
            local column = entry.col + 1 + (entry.dir == "H" and index - 1 or 0)
            local letter = entry.word:sub(index, index)
            assert(puzzle.letters[row][column] == "" or puzzle.letters[row][column] == letter, "Conflicting crossing")
            puzzle.letters[row][column] = letter
            placed.path[index] = {row=row, column=column}
        end
        table.insert(puzzle.words, id)
        puzzle.placedWordsByWord[id] = placed
    end
    return puzzle
end

function Generator.Generate(definition, seed)
    assert(definition.rules == "Crossword", "Only crossword definitions are supported")
    seed = seed or definition.seed or math.max(1, DateTime.now().UnixTimestampMillis % 2147483647)
    if definition.tutorial then
        -- CAT crosses CAR at C; RED crosses CAR at R.
        -- Three familiar answers: CAT, CAR, RED. All entries are connected.
        return assemble({title="First Crossword", subtitle="Three little clues", rows=3, cols=3, entries={
            {word="CAT", clue="A pet that says meow", row=0, col=0, dir="H", number=1},
            {word="CAR", clue="A vehicle with four wheels", row=0, col=0, dir="V", number=1},
            {word="RED", clue="The colour of a ripe tomato", row=2, col=0, dir="H", number=2},
        }}, definition, seed)
    end
    local pool = {}
    local easy = definition.beginner or definition.mode == "Mini"
    for _, entry in ipairs(Bank) do
        if #entry.word <= definition.gridSize and (not easy or entry.difficulty == "Easy") then
            table.insert(pool, entry)
        end
    end
    local board = Layout.build(pool, seed, "round", "Crosswords", {
        maxSize=definition.gridSize, minEntries=definition.wordCount, maxEntries=definition.wordCount,
        attempts=24, poolSize=#pool,
    })
    return assemble(board, definition, seed)
end
Generator.generate = Generator.Generate
return Generator

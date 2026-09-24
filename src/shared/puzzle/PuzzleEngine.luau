-- Crossword protocol helpers. Canonical answers exist only on the server.
local Engine = {}
function Engine.NormalizeAnswer(value)
    if type(value) ~= "string" or #value < 1 or #value > 32 or not value:match("^[A-Za-z]+$") then return nil end
    return string.upper(value)
end
function Engine.Entry(puzzle, id)
    return type(id) == "string" and type(puzzle) == "table" and puzzle.placedWordsByWord[id] or nil
end
-- Nil is malformed/incomplete; false is a full incorrect answer (Hardcore loss).
function Engine.CheckAnswer(puzzle, id, answer)
    local entry = Engine.Entry(puzzle, id)
    local normalized = Engine.NormalizeAnswer(answer)
    if not entry or not normalized or #normalized ~= entry.length or type(entry.answer) ~= "string" then return nil end
    return normalized == entry.answer
end
function Engine.RevealedAnswers(puzzle, found, hinted)
    local result = {}
    for _, id in ipairs(puzzle.words) do
        if found[id] or (hinted and hinted[id]) then result[id] = puzzle.placedWordsByWord[id].answer end
    end
    return result
end
function Engine.PublicPuzzle(puzzle)
    local result = {rules="Crossword", title=puzzle.title, subtitle=puzzle.subtitle,
        tutorial=puzzle.tutorial, level=puzzle.level, mode=puzzle.mode,
        gridSize=puzzle.gridSize, gridWidth=puzzle.gridWidth, words=table.clone(puzzle.words),
        letters={}, placedWordsByWord={}}
    for row, letters in ipairs(puzzle.letters) do
        result.letters[row] = {}
        for column, letter in ipairs(letters) do result.letters[row][column] = letter == "" and "" or " " end
    end
    for _, id in ipairs(puzzle.words) do
        local entry = puzzle.placedWordsByWord[id]
        local path = {}
        for i, cell in ipairs(entry.path) do path[i] = {row=cell.row, column=cell.column} end
        result.placedWordsByWord[id] = {id=id, number=entry.number, direction=entry.direction,
            clue=entry.clue, length=entry.length, path=path}
    end
    return result
end
function Engine.IsComplete(words, found)
    for _, id in ipairs(words) do if not found[id] then return false end end
    return #words > 0
end
return Engine

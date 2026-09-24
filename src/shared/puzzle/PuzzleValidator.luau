local Engine = if script then require(script.Parent.PuzzleEngine) else require("./PuzzleEngine")
local Validator = {CheckAnswer=Engine.CheckAnswer, PublicPuzzle=Engine.PublicPuzzle, RevealedAnswers=Engine.RevealedAnswers}
function Validator.NormalizeWord(value)
    if type(value) ~= "string" or #value > 8 or not value:match("^%d+[AD]$") then return nil end
    return value
end
function Validator.ValidateDefinition(definition)
    if type(definition) ~= "table" or definition.rules ~= "Crossword" then return false, "Expected crossword definition" end
    local size, count = definition.gridSize, definition.wordCount
    if type(size) ~= "number" or size % 1 ~= 0 or size < 3 or size > 15
        or type(count) ~= "number" or count % 1 ~= 0 or count < 3 or count > 12 then
        return false, "Invalid crossword size or clue count"
    end
    return true
end
return Validator

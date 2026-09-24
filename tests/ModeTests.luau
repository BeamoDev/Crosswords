require("../src/shared/puzzle/PuzzleTests.spec")
local Generator = require("../src/shared/puzzle/PuzzleGenerator")
local Engine = require("../src/shared/puzzle/PuzzleEngine")
local Validator = require("../src/shared/puzzle/PuzzleValidator")
local Catalog = require("../src/shared/content/PuzzleCatalog")
local Queue = require("../src/server/services/QueueState")
local checks, totalBoards, bentBoards = 0, 0, 0
local orientations = {}
local function check(value, reason) assert(value, reason) checks += 1 end
local function verify(definition, seed)
    check(Validator.ValidateDefinition(definition), "Definition validates")
    local ok, puzzle = pcall(Generator.Generate, definition, seed)
    assert(ok, tostring(Catalog.GetThemes()[1].title) .. "/" .. tostring(definition.mode) .. "/" .. seed .. ": " .. tostring(puzzle))
    totalBoards += 1
    local h, w = definition.gridSize, definition.gridWidth
    check(puzzle.rules == "Strands" and #puzzle.letters == h, "Bending rules and height")
    check(h == w and puzzle.gridWidth == w and puzzle.gridSize == h, "Dimensions describe actual grid")
    local vocabulary = {}
    for _, theme in ipairs(definition.beginner and Catalog.BeginnerThemes or Catalog.GetThemes()) do
        if theme.title == puzzle.theme then
            for _, word in ipairs(theme.words) do vocabulary[word] = true end
        end
    end
    local covered, count, bends = {}, 0, 0
    local round = Queue.NewRound("test", puzzle, {{userId=1},{userId=2}})
    for _, word in ipairs(puzzle.words) do
        check(vocabulary[word], "Every answer, including the spanning word, belongs to its authored theme vocabulary: " .. word)
        local path = puzzle.placedWordsByWord[word].path
        local bucketName = definition.beginner and "Beginner" or definition.mode
        local counts = orientations[bucketName] or {total=0, backwards=0}
        orientations[bucketName] = counts
        counts.total += 1
        local first, last = path[1], path[#path]
        local horizontal = math.abs(last.column-first.column) >= math.abs(last.row-first.row)
        if (horizontal and last.column<first.column) or (not horizontal and last.row<first.row) then counts.backwards += 1 end
        check(#path == #word and Engine.ReadAdjacentWord(puzzle.letters, path) == word, "Every path spells its word with adjacent unique tiles")
        local lastR, lastC
        for i, cell in ipairs(path) do
            local key = cell.row .. ":" .. cell.column
            check(not covered[key], "No words share a tile")
            covered[key], count = true, count + 1
            if i > 1 then
                local dr, dc = cell.row-path[i-1].row, cell.column-path[i-1].column
                if lastR and (dr ~= lastR or dc ~= lastC) then bends += 1 end
                lastR, lastC = dr, dc
            end
        end
        check(round:FindWord(1, word, path), "Server accepts each canonical bending path")
        check(not round:FindWord(1, word, path), "Duplicates cannot advance progress")
    end
    check(count == h*w and round.members[1].completed and round.members[2].count == 0, "Complete coverage and independent human progress")
    for _, row in ipairs(puzzle.letters) do check(#row == w, "No missing cells or ragged rows") end
    local span = assert(puzzle.placedWordsByWord[puzzle.spangram], "Spangram is an actual answer")
    local top,bottom,left,right = false,false,false,false
    for _, c in ipairs(span.path) do
        top,bottom = top or c.row==1,bottom or c.row==h
        left,right = left or c.column==1,right or c.column==w
    end
    check(top and bottom or left and right, "Spangram touches opposite sides")
    if bends > 0 then bentBoards += 1 end
    return puzzle
end
local original = Catalog.GetThemes
for _, theme in ipairs(original()) do
    Catalog.GetThemes = function() return {theme} end
    for _, mode in ipairs({"Standard","Mini","Jumbo","Hardcore","Duel","Timed"}) do
        for sample = 1, 4 do verify(Generator.BuildDefinition(1, mode, sample*7919), sample*7919) end
    end
end
Catalog.GetThemes = original
for _, mode in ipairs({"Standard","Mini","Jumbo","Hardcore","Duel","Timed"}) do
    local signatures = {}
    for sample = 1, 100 do
        local seed = sample == 100 and 2147483646 or sample*7919
        local definition = Generator.BuildDefinition(1,mode,seed)
        local puzzle = verify(definition,seed)
        local signature = ""
        for _, row in ipairs(puzzle.letters) do signature ..= table.concat(row) end
        signatures[signature] = true
        if sample == 1 then
            local reverseRound = Queue.NewRound("reverse-"..mode,puzzle,{{userId=9}},mode)
            local answer = puzzle.words[1]
            local forward, reverse = puzzle.placedWordsByWord[answer].path, {}
            for index = #forward, 1, -1 do table.insert(reverse, forward[index]) end
            check(require("../src/shared/puzzle/PuzzleValidator").ValidateStrand(puzzle,reverse,answer), "Duel/shared validator accepts reversed path in "..mode)
            check(reverseRound:FindWord(9,answer,reverse), "Reversed answer accepted in "..mode)
            check(not reverseRound:FailSelection(9,reverse), "Reversed duplicate cannot cause Hardcore loss")
            local again = Generator.Generate(definition,seed)
            local repeated = ""
            for _, row in ipairs(again.letters) do repeated ..= table.concat(row) end
            check(signature == repeated and puzzle.spangram == again.spangram, "Same seed reproduces board and span")
        end
    end
    local count = 0 for _ in pairs(signatures) do count += 1 end
    check(count > 90, "Seeds vary the board in " .. mode)
end
for solves = 0, 13 do
    for sample = 1, 40 do
        local definition = Generator.BuildClassicDefinition({},sample*17137,solves)
        local puzzle = verify(definition,sample*17137)
        check(puzzle.gridSize == (solves<10 and 5 or 7) and puzzle.gridWidth == puzzle.gridSize, "Saved solves choose beginner dimensions")
    end
end
do
    local beginnerThemes = Catalog.BeginnerThemes
    for _, theme in ipairs(beginnerThemes) do
        Catalog.BeginnerThemes = {theme}
        for sample = 1, 20 do
            local puzzle = verify(Generator.BuildClassicDefinition({},sample*9137,0),sample*9137)
            check(puzzle.theme == theme.title, "Every beginner theme remains available")
            check(not puzzle.placedWordsByWord.YUMMYFOOD and not puzzle.placedWordsByWord.LETSPLAY
                and not puzzle.placedWordsByWord.ATHOME, "Theme titles cannot become joined-up answers")
        end
    end
    Catalog.BeginnerThemes = beginnerThemes
end
for mode,counts in pairs(orientations) do
    local ratio = counts.backwards / counts.total
    local easy = mode == "Beginner" or mode == "Mini"
    check(counts.total > 500 and ratio >= (easy and 0.015 or 0.10) and ratio <= (easy and 0.085 or 0.20), "Backward placements stay uncommon across seeded boards in "..mode..": "..ratio)
    print(string.format("BACKWARDS_%s=%.1f%% (%d words)",mode,ratio*100,counts.total))
end
check(bentBoards == totalBoards, "Every generated board includes a bend")
for _, mode in ipairs({"Classic","Themed","Freeplay","Unknown"}) do
    check(not pcall(Generator.BuildDefinition,1,mode,1), "Retired modes reject")
end
local letters = {{"C","A","X"},{"A","T","Y"},{"Z","Q","Z"}}
local path = {{row=1,column=1},{row=1,column=2},{row=2,column=2}}
check(Engine.ReadAdjacentWord(letters,path)=="CAT", "A bent path is valid")
check(not Engine.ReadAdjacentWord(letters,{{row=1,column=1},{row=3,column=3}}), "Cannot skip tiles")
check(not Engine.ReadAdjacentWord(letters,{{row=1,column=1},{row=1,column=2},{row=1,column=1}}), "Cannot reuse a tile")
check(not Engine.ReadAdjacentWord(letters,{{row=0,column=1}}), "Off-board rejects")
check(not Engine.ReadAdjacentWord(letters,{{row=0/0,column=1}}), "Nonfinite coordinates reject")
local p = {rules="Strands", letters=letters, words={"CAT"}, placedWordsByWord={CAT={path=path}}}
check(not Engine.MatchesStrand(p,"CAT",{{row=1,column=1},{row=2,column=1},{row=2,column=2}}), "Cannot borrow another word's same-letter tile")
local selection = {path[1]}
check(Engine.ExtendAdjacentPath(selection,path[2]) and Engine.ExtendAdjacentPath(selection,path[3]), "Drag can bend")
check(Engine.ExtendAdjacentPath(selection,path[2]) and #selection==2, "Backtracking removes the last tile")
check(not Engine.ExtendAdjacentPath(selection,{row=3,column=3}), "Input ignores jumps")
local hard = Queue.NewRound("hard",p,{{userId=1}},"Hardcore")
local reverse = {path[3],path[2],path[1]}
check(Engine.MatchesStrand(p,"CAT",reverse), "Shared matcher accepts backward bending words")
check(not hard:FailSelection(1,reverse), "Correct reversed word never loses Hardcore")
local backwards = Queue.NewRound("reverse",p,{{userId=1}},"Standard")
check(backwards:FindWord(1,"CAT",reverse), "Server accepts reversed traversal")
check(not backwards:FindWord(1,"CAT",path), "Forward submission after reversed solve cannot award twice")
check(not hard:FailSelection(1,path), "Correct bending word never loses")
check(not hard:FailSelection(1,{{row=1,column=1},{row=1,column=2}}), "Too-short gestures never lose")
check(not hard:FailSelection(1,{{row=1,column=1},{row=1,column=2},{row=1,column=1}}), "Invalid geometry never loses")
check(hard:FailSelection(1,{{row=1,column=1},{row=2,column=1},{row=2,column=2}})==false, "Alternative spelling of a theme word does not cause loss")
check(hard:FailSelection(1,{{row=1,column=1},{row=2,column=1},{row=3,column=2}}), "Actual bent wrong word loses Hardcore")
check(not hard:FindWord(1,"CAT",path), "Failed rounds cannot award a later word")
do
	local Dictionary = require("../src/shared/content/EnglishDictionary")
	for _, word in ipairs({"COT","ATE","EAT","TEA","READ","READS","READING","QUIZZES","ZYMURGY"}) do check(Dictionary.Contains(word), "Dictionary accepts common words, inflections and end-of-alphabet entries") end
	check(not Dictionary.Contains("QQQ") and not Dictionary.Contains("AB") and not Dictionary.Contains("cat"), "Dictionary rejects invalid spelling, short words and unnormalized input")
	local bonus = Queue.NewRound("bonus",p,{{userId=1},{userId=2,isBot=true}},"Hardcore")
	local alternate = {{row=1,column=1},{row=2,column=1},{row=2,column=2}}
	check(bonus:FindBonusWord(1,alternate)=="CAT" and not bonus:FailSelection(1,alternate), "Valid alternate answer tiles earn bonus and never lose Hardcore")
	check(not bonus:FindBonusWord(1,alternate) and not bonus:FindBonusWord(2,alternate), "Duplicate bonuses and bots never qualify")
	check(bonus:FindWord(1,"CAT",path), "Finding a bonus never blocks canonical theme completion")
	local practice = Generator.Generate(Generator.BuildTutorialDefinition(1),1)
	check(not Engine.ReadBonusWord(practice,practice.placedWordsByWord.CAT.path), "Tutorial remains reward-free")
end
print("STRANDS_BOARDS="..totalBoards.." MODE_TESTS_PASSED="..checks)

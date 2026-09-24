local Generator = require("../src/server/puzzle/PuzzleGenerator")
local Engine = require("../src/shared/puzzle/PuzzleEngine")
local Validator = require("../src/shared/puzzle/PuzzleValidator")
local Bank = require("../src/server/content/CrosswordBank")
local Queue = require("../src/server/services/QueueState")
local Editing = require("../src/shared/puzzle/CrosswordInput")
local Contract = require("../src/shared/network/NetworkContract")
local checks, boards = 0, 0
local function check(value,message) assert(value,message) checks+=1 end
local function key(cell) return cell.row..":"..cell.column end
local function fingerprint(puzzle)
    local parts={}
    for _,id in ipairs(puzzle.words) do
        local e=puzzle.placedWordsByWord[id]
        table.insert(parts,id..":"..e.answer..":"..key(e.path[1]))
    end
    return table.concat(parts,"|")
end
local vocabulary={}
for _,e in ipairs(Bank) do
    check(not vocabulary[e.word] and e.word:match("^[A-Z]+$") and #e.clue>5,"Unique authored vocabulary with usable clues")
    vocabulary[e.word]=e.clue
end
local function verify(definition,seed)
    check(Validator.ValidateDefinition(definition),"Definition validates")
    local p=Generator.Generate(definition,seed)
    boards+=1
    check(p.rules=="Crossword" and #p.words==definition.wordCount,"Exact requested clue count")
    check(#p.letters==p.gridSize and #p.letters[1]==p.gridWidth and p.gridSize<=definition.gridSize and p.gridWidth<=definition.gridWidth,"Bounded dimensions match actual matrix")
    local occupied,starts,numbers={}, {}, {}
    for _,id in ipairs(p.words) do
        local e=p.placedWordsByWord[id]
        check(vocabulary[e.answer]==e.clue or p.tutorial,"Answers and clues come from authored bank")
        check(e.length==#e.answer and e.length==#e.path,"Entry length agrees")
        check(id==tostring(e.number)..(e.direction=="Across" and "A" or "D"),"Stable entry IDs")
        local start=key(e.path[1]);starts[start]=e.number
        if numbers[e.number] then check(numbers[e.number]==start,"Shared numbers share a starting square") else numbers[e.number]=start end
        for i,cell in ipairs(e.path) do
            check(p.letters[cell.row][cell.column]==e.answer:sub(i,i),"Every crossing spells both answers")
            local k=key(cell);occupied[k]=occupied[k] or {}
            table.insert(occupied[k],id)
            check(#occupied[k]<=2,"No more than two entries share a square")
            if i>1 then
                local prev=e.path[i-1]
                check(cell.row-prev.row==(e.direction=="Down" and 1 or 0) and cell.column-prev.column==(e.direction=="Across" and 1 or 0),"Straight forward Across/Down geometry")
            end
        end
        check(Engine.CheckAnswer(p,id,string.lower(e.answer))==true,"Answer accepted case-insensitively")
        check(Engine.CheckAnswer(p,id,e.path)==nil and Engine.CheckAnswer(p,id,e.answer:sub(2))==nil,"Paths and incomplete answers rejected")
    end
    -- Every nontrivial horizontal/vertical run must have exactly one clue.
    local startDirection={}
    for _,id in ipairs(p.words) do local e=p.placedWordsByWord[id];startDirection[key(e.path[1])..e.direction]=e.length end
    for r,row in ipairs(p.letters) do for c,letter in ipairs(row) do
        if letter~="" then
            check(occupied[r..":"..c]~=nil,"No orphan letters")
            for _,axis in ipairs({{0,1,"Across"},{1,0,"Down"}}) do
                local dr,dc,dir=table.unpack(axis)
                local before=p.letters[r-dr] and p.letters[r-dr][c-dc]
                if not before or before=="" then
                    local length=0
                    while p.letters[r+dr*length] and p.letters[r+dr*length][c+dc*length] and p.letters[r+dr*length][c+dc*length]~="" do length+=1 end
                    if length>1 then check(startDirection[r..":"..c..dir]==length,"No accidental unclued runs") end
                end
            end
        end
    end end
    local reached={[p.words[1]]=true}
    for _=1,#p.words do for _,ids in pairs(occupied) do
        if #ids==2 and (reached[ids[1]] or reached[ids[2]]) then reached[ids[1]],reached[ids[2]]=true,true end
    end end
    for _,id in ipairs(p.words) do check(reached[id],"All entries form one connected crossword") end
    local public=Engine.PublicPuzzle(p)
    check(public.seed==nil and public.placedWordsByWord[p.words[1]].answer==nil,"Public metadata excludes seed and answers")
    for _,row in ipairs(public.letters) do for _,letter in ipairs(row) do check(letter=="" or letter==" ","Public cells never expose solution letters") end end
    local round=Queue.NewRound("test",p,{{userId=1},{userId=2}},"Hardcore")
    local id=p.words[1];local e=p.placedWordsByWord[id]
    check(not round:FindWord(1,id,e.path) and not round:FailSelection(1,id,e.path),"Old path protocol cannot solve or lose")
    check(round:MarkHint(1,id),"Hint marks one entry")
    local snapshot=round:Snapshot(true,1)
    check(snapshot.members[1].revealedAnswers[id]==e.answer and snapshot.members[2].revealedAnswers==nil,"Hint belongs only to requesting player")
    check(round:Snapshot(false,2).members[1].revealedAnswers==nil,"Opponent cannot receive hinted answer")
    for _,word in ipairs(p.words) do check(round:FindWord(1,word,p.placedWordsByWord[word].answer),"Correct answer completes once") end
    check(round.members[1].completed and not round.members[2].completed,"Independent completion")
    check(not round:FindWord(1,id,e.answer),"Duplicate cannot award score")
    return p
end
for _,mode in ipairs({"Standard","Mini","Jumbo","Hardcore","Duel","Timed"}) do
    local unique={}
    for seed=1,120 do
        local d=Generator.BuildDefinition(1,mode,seed*7919)
        local p=verify(d,seed*7919)
        unique[fingerprint(p)]=true
        if seed<=3 then check(fingerprint(p)==fingerprint(Generator.Generate(d,seed*7919)),"Seeded generation deterministic") end
    end
    local n=0 for _ in pairs(unique) do n+=1 end
    check(n>110,"Seeds provide varied crosswords")
    print("VERIFIED_MODE="..mode)
end
for seed=1,120 do verify(Generator.BuildClassicDefinition({},seed,0),seed) end
verify(Generator.BuildTutorialDefinition(1),1)
check(Generator.BuildClassicDefinition({},1,9).wordCount==5 and Generator.BuildClassicDefinition({},1,10).wordCount==7,"Beginner graduation keeps ten-solve gate")
check(not pcall(Generator.BuildDefinition,1,"Classic",1),"Retired mode rejected")
local p=Generator.Generate(Generator.BuildTutorialDefinition(1),1)
local edit=Editing.new(Engine.PublicPuzzle(p))
edit:Type("C") edit:Type("A") edit:Type("T")
check(edit:Answer()=="CAT","Typed answer assembled")
edit:Apply({["1A"]=true},{["1A"]="CAT"}) edit:Select("1D")
edit:Type("A") edit:Type("R")
check(edit:Answer()=="CAR" and edit.draft["3:1"]=="R","Crossing filled and locked letters skipped")
edit:Select("2A") edit:Type("E") edit:Type("D")
check(edit:Answer()=="RED","Unconfirmed draft crossing is shared")
edit:Backspace() check(edit:Answer()==nil,"Erase removes last typed letter")
edit:Apply({["1A"]=true},{["1A"]="CAT",["1D"]="CAR"})
edit:Select("1D") edit:Backspace()
check(edit.locked["1:1"]=="C" and edit.locked["3:1"]=="R","Hints/solves cannot be erased")
edit:Select("2A") edit:SetAnswer("r-e-d!")
check(edit:Answer()=="RED","Native whole-answer typing sanitizes text and keeps shared locks")
edit:SetAnswer("bad")
check(edit:Answer()=="RAD","Native typing cannot overwrite a revealed crossing")
local round=Queue.NewRound("hard",p,{{userId=1}},"Hardcore")
check(not round:FailSelection(1,"1A","CA") and not round:FailSelection(1,"missing","CAT"),"Malformed/incomplete attempts do not lose")
check(round:FailSelection(1,"1A","DOG") and not round:FindWord(1,"1A","CAT"),"Full wrong answer loses Hardcore and blocks late solve")
check(not Contract.IsBoundedValue(string.rep("A",257)) and not Contract.IsBoundedValue(0/0),"Network rejects unbounded strings and NaN")
print("CROSSWORD_TESTS_PASSED="..checks.." BOARDS="..boards)

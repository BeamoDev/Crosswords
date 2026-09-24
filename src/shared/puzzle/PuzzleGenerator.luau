local Strands = if script then require(script.Parent.StrandsGenerator) else require("./StrandsGenerator")
local PuzzleGenerator = { BeginnerSolves = 10 }
local sizes = {
    Standard = {7, 7}, Mini = {5, 5}, Jumbo = {8, 8},
    Hardcore = {7, 7}, Duel = {7, 7}, Timed = {7, 7},
}

function PuzzleGenerator.BuildDefinition(level, mode, seed)
    local size = assert(sizes[mode], "Unsupported puzzle mode: " .. tostring(mode))
    return {level=level, mode=mode, rules="Strands", seed=seed, gridSize=size[1], gridWidth=size[2]}
end

function PuzzleGenerator.BuildClassicDefinition(_members, seed, solves)
    local definition = PuzzleGenerator.BuildDefinition(1, "Standard", seed)
    definition.beginner = type(solves) == "number" and solves < PuzzleGenerator.BeginnerSolves
    if definition.beginner then definition.gridSize, definition.gridWidth = 5, 5 end
    return definition
end

function PuzzleGenerator.BuildTutorialDefinition(seed)
    return {level=1, mode="Standard", rules="Strands", tutorial=true, seed=seed, gridSize=3, gridWidth=3}
end

function PuzzleGenerator.generate(definition, seed)
    assert(definition.rules == "Strands", "Only Strands puzzle definitions are supported")
    return Strands.Generate(definition, seed or definition.seed or math.max(1, DateTime.now().UnixTimestampMillis % 2147483647))
end
PuzzleGenerator.Generate = PuzzleGenerator.generate
return PuzzleGenerator

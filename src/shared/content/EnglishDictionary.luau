-- Offline English word membership. Loads only the alphabetical shard requested.
-- ENABLE2K by Alan Beale and M. Cooper, public domain; see THIRD_PARTY_NOTICES.md.
local shards = {
    {last="BIRDSEYE", name="Part01"},
    {last="CONGII", name="Part02"},
    {last="DOMINEER", name="Part03"},
    {last="FRONTALS", name="Part04"},
    {last="INCREMENTING", name="Part05"},
    {last="MAUDLIN", name="Part06"},
    {last="OTIC", name="Part07"},
    {last="PREROGATIVED", name="Part08"},
    {last="RUMORMONGERS", name="Part09"},
    {last="SUBGUMS", name="Part10"},
    {last="UNFORMED", name="Part11"},
    {last="ZYZZYVAS", name="Part12"},
}
local Dictionary = {}
function Dictionary.Contains(word)
    if type(word) ~= "string" or #word < 3 or #word > 32 or not word:match("^[A-Z]+$") then return false end
    for _, shard in ipairs(shards) do
        if word <= shard.last then
            if not shard.words then
                shard.words = if script then require(script.Parent.EnglishWords:WaitForChild(shard.name))
                    else require("./EnglishWords/" .. shard.name)
            end
            return shard.words:find("\n" .. word .. "\n", 1, true) ~= nil
        end
    end
    return false
end
return Dictionary

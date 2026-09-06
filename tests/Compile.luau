local fs = require("@lune/fs")
local luau = require("@lune/luau")
local count = 0
local function visit(path)
	for _, name in ipairs(fs.readDir(path)) do
		local file = path .. "/" .. name
		if fs.isDir(file) then visit(file)
		elseif string.sub(name, -5) == ".luau" then
			local ok, err = pcall(luau.compile, fs.readFile(file))
			assert(ok, file .. ": " .. tostring(err))
			count += 1
		end
	end
end
visit("src")
visit("tests")
print("LUAU_COMPILE_PASSED=" .. count)

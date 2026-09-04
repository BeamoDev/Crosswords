local WordPathUtils = {}

function WordPathUtils.NormalizeWord(word)
	if type(word) ~= "string" then
		return nil
	end

	local normalized = string.upper(word:gsub("%s+", ""))
	if normalized == "" then
		return nil
	end

	return normalized
end

function WordPathUtils.SanitizePath(path)
	if type(path) ~= "table" then
		return nil
	end

	local sanitized = {}
	for index, point in ipairs(path) do
		if type(point) ~= "table" then
			return nil
		end

		local row = math.floor(tonumber(point.row) or 0)
		local column = math.floor(tonumber(point.column) or 0)
		if row <= 0 or column <= 0 then
			return nil
		end

		sanitized[index] = {
			row = row,
			column = column,
		}
	end

	return #sanitized > 0 and sanitized or nil
end

function WordPathUtils.PathsMatch(expectedPath, claimedPath)
	local left = WordPathUtils.SanitizePath(expectedPath)
	local right = WordPathUtils.SanitizePath(claimedPath)
	if not left or not right or #left ~= #right then
		return false
	end

	for index = 1, #left do
		local expected = left[index]
		local claimed = right[index]
		if expected.row ~= claimed.row or expected.column ~= claimed.column then
			return false
		end
	end

	return true
end

return WordPathUtils

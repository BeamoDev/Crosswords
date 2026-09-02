local TableUtils = {}

function TableUtils.CloneDeep(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = TableUtils.CloneDeep(child)
	end
	return copy
end

function TableUtils.MergeDefaults(target, defaults)
	if type(defaults) ~= "table" then
		return target
	end

	if type(target) ~= "table" then
		return TableUtils.CloneDeep(defaults)
	end

	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = TableUtils.CloneDeep(value)
		elseif type(target[key]) == "table" and type(value) == "table" then
			TableUtils.MergeDefaults(target[key], value)
		end
	end

	return target
end

return TableUtils

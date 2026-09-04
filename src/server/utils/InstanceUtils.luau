local InstanceUtils = {}

function InstanceUtils.GetOrCreate(parent, className, name)
	local child = parent:FindFirstChild(name)
	if child then
		return child
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

return InstanceUtils

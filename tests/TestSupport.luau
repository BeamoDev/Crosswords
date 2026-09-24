-- Deterministic Lune stand-in for Roblox Random.
	if not Random then
		Random = {
			new = function(seed)
				local state = math.max(1, math.floor(tonumber(seed) or 1) % 2147483647)
				return {
					NextInteger = function(_, minimum, maximum)
						state = (state * 48271) % 2147483647
						return minimum + (state % (maximum - minimum + 1))
					end,
				}
			end,
		}
	end
return {}

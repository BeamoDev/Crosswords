-- Small per-player token bucket used by the revamp remotes. Buckets are keyed by
-- endpoint so an expensive request cannot be hidden inside another endpoint's quota.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(defaultCapacity, defaultRefillPerSecond)
	return setmetatable({
		defaultCapacity = math.max(1, tonumber(defaultCapacity) or 8),
		defaultRefillPerSecond = math.max(0.01, tonumber(defaultRefillPerSecond) or 4),
		players = {},
	}, RateLimiter)
end

function RateLimiter:Allow(player, endpoint, cost, capacity, refillPerSecond)
	if not player then
		return false
	end

	local userId = player.UserId
	local now = os.clock()
	local endpointKey = tostring(endpoint or "default")
	local playerBuckets = self.players[userId]
	if not playerBuckets then
		playerBuckets = {}
		self.players[userId] = playerBuckets
	end

	local bucketCapacity = math.max(1, tonumber(capacity) or self.defaultCapacity)
	local refill = math.max(0.01, tonumber(refillPerSecond) or self.defaultRefillPerSecond)
	local bucket = playerBuckets[endpointKey]
	if not bucket then
		bucket = { tokens = bucketCapacity, updatedAt = now }
		playerBuckets[endpointKey] = bucket
	end

	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.updatedAt = now
	bucket.tokens = math.min(bucketCapacity, bucket.tokens + elapsed * refill)

	local requestedCost = math.max(0.01, tonumber(cost) or 1)
	if bucket.tokens < requestedCost then
		return false
	end

	bucket.tokens -= requestedCost
	return true
end

function RateLimiter:ClearPlayer(player)
	if player then
		self.players[player.UserId] = nil
	end
end

return RateLimiter

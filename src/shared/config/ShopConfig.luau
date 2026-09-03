-- All identifiers and prices are server-readable. Robux offers remain disabled
-- until a real Developer Product ID is configured; no fake IDs are shipped.
local ShopConfig = {}

local dailyRewards = {
	{ coins = 40, hints = 0 },
	{ coins = 55, hints = 0 },
	{ coins = 70, hints = 1 },
	{ coins = 85, hints = 0 },
	{ coins = 100, hints = 1 },
	{ coins = 125, hints = 1 },
	{ coins = 200, hints = 2 },
}

local products = {
	{ id = "hints-three", title = "3 Hint Pack", description = "Reveal three starting letters.", kind = "Hints", amount = 3, coinPrice = 90, accent = "Info" },
	{ id = "hints-ten", title = "10 Hint Pack", description = "A bigger boost for hard grids.", kind = "Hints", amount = 10, coinPrice = 260, accent = "Success" },
	{ id = "theme-sky", title = "Sky Glass", description = "A crisp cyan-and-navy interface theme.", kind = "Theme", itemId = "SkyGlass", coinPrice = 300, accent = "Info" },
	{ id = "theme-sunset", title = "Sunset Glow", description = "Warm gold accents over blue glass.", kind = "Theme", itemId = "SunsetGlow", coinPrice = 450, accent = "Gold" },
	{ id = "trail-prism", title = "Prism Trail", description = "A vivid selection trail style.", kind = "Trail", itemId = "Prism", coinPrice = 375, accent = "Success" },
	{ id = "background-clouds", title = "Cloud Vista", description = "An airy menu background treatment.", kind = "Background", itemId = "CloudVista", coinPrice = 500, accent = "Info" },
	{ id = "ui-rounded", title = "Bubble Grid", description = "Extra-rounded puzzle tiles.", kind = "UIStyle", itemId = "BubbleGrid", coinPrice = 425, accent = "Gold" },
	{ id = "coins-small", title = "Coin Pouch", description = "Requires a configured Developer Product ID.", kind = "CoinPack", amount = 500, developerProductId = nil, disabled = true, accent = "Gold" },
	{ id = "coins-large", title = "Coin Chest", description = "Requires a configured Developer Product ID.", kind = "CoinPack", amount = 1800, developerProductId = nil, disabled = true, accent = "Gold" },
}

local productsById = {}
for index, reward in ipairs(dailyRewards) do
	dailyRewards[index] = table.freeze(reward)
end
for index, product in ipairs(products) do
	local frozenProduct = table.freeze(product)
	products[index] = frozenProduct
	productsById[frozenProduct.id] = frozenProduct
end
productsById = table.freeze(productsById)

ShopConfig.DailyRewards = table.freeze(dailyRewards)
ShopConfig.Products = table.freeze(products)

function ShopConfig.GetProduct(productId)
	return type(productId) == "string" and productsById[productId] or nil
end

function ShopConfig.GetDailyReward(dayStamp)
	local index = (math.max(0, math.floor(tonumber(dayStamp) or 0)) % #ShopConfig.DailyRewards) + 1
	return ShopConfig.DailyRewards[index], index
end

return table.freeze(ShopConfig)

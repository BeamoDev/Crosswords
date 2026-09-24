-- Deterministic, bounded crossword generation from the authored level bank.
local Generator = {}
local function key(r, c) return r .. ":" .. c end
function Generator.build(bank, seed, id, title, options)
	options = options or {}
	local maxEntries, minEntries, maxSize = options.maxEntries or 9, options.minEntries or 6, options.maxSize or 13
	local function random(n)
		seed = (seed * 1664525 + 1013904223) % 4294967296
		return math.floor(seed / 4294967296 * n) + 1
	end
	local best
	for _ = 1, options.attempts or 8 do
		local pool = table.clone(bank)
		for i = #pool, 2, -1 do local j = random(i) pool[i], pool[j] = pool[j], pool[i] end
		local grid, cells, entries = {}, {}, {}
		local minR, minC, maxR, maxC = 0, 0, 0, 0
		local function place(source, r, c, dir)
			local entry = {word = source.word, clue = source.clue, sourceId = source.sourceId, row = r, col = c, dir = dir}
			table.insert(entries, entry)
			for j = 0, #entry.word - 1 do
				local rr, cc = r + (dir == "V" and j or 0), c + (dir == "H" and j or 0)
				local k = key(rr, cc)
				if not grid[k] then
					grid[k] = {row = rr, col = cc, letter = entry.word:sub(j + 1, j + 1), dirs = {}}
					table.insert(cells, grid[k])
				end
				grid[k].dirs[dir] = true
				minR, minC = math.min(minR, rr), math.min(minC, cc)
				maxR, maxC = math.max(maxR, rr), math.max(maxC, cc)
			end
		end
		place(pool[1], 0, 0, "H")
		for i = 2, math.min(options.poolSize or 100, #pool) do
			local source, choice = pool[i], nil
			for _, cell in ipairs(cells) do
				for j = 1, #source.word do
					if source.word:sub(j, j) == cell.letter then
						for _, dir in ipairs({"H", "V"}) do
							local dr, dc = dir == "V" and 1 or 0, dir == "H" and 1 or 0
							local r, c = cell.row - dr * (j - 1), cell.col - dc * (j - 1)
							local er, ec = r + dr * (#source.word - 1), c + dc * (#source.word - 1)
							local rows = math.max(maxR, er) - math.min(minR, r) + 1
							local cols = math.max(maxC, ec) - math.min(minC, c) + 1
							local valid = rows <= maxSize and cols <= maxSize and not grid[key(r - dr, c - dc)] and not grid[key(er + dr, ec + dc)]
							local crosses, added = 0, 0
							if valid then
								for offset = 0, #source.word - 1 do
									local rr, cc = r + dr * offset, c + dc * offset
									local existing = grid[key(rr, cc)]
									if existing then
										if existing.letter ~= source.word:sub(offset + 1, offset + 1) or existing.dirs[dir] then valid = false break end
										crosses += 1
									else
										if grid[key(rr + dc, cc + dr)] or grid[key(rr - dc, cc - dr)] then valid = false break end
										added += 1
									end
								end
							end
							if valid and crosses > 0 and added > 0 then
								local score = rows * cols + 6 * math.abs(rows - cols) - 25 * crosses
								if not choice or score < choice.score then choice = {r = r, c = c, dir = dir, score = score} end
							end
						end
					end
				end
			end
			if choice then place(source, choice.r, choice.c, choice.dir) end
			if #entries >= maxEntries then break end
		end
		local sources = {}
		for _, entry in ipairs(entries) do sources[entry.sourceId] = true end
		local sourceCount = 0 for _ in pairs(sources) do sourceCount += 1 end
		if sourceCount >= 2 and (not best or #entries > #best.entries) then
			best = {entries = entries, minR = minR, minC = minC, rows = maxR - minR + 1, cols = maxC - minC + 1}
		end
		if best and #best.entries == maxEntries then break end
	end
	assert(best and #best.entries >= minEntries, "Could not generate a connected crossword")
	for _, entry in ipairs(best.entries) do entry.row -= best.minR entry.col -= best.minC end
	table.sort(best.entries, function(a, b)
		if a.row ~= b.row then return a.row < b.row end
		if a.col ~= b.col then return a.col < b.col end
		return a.dir < b.dir
	end)
	local starts, number = {}, 0
	for _, entry in ipairs(best.entries) do
		local k = key(entry.row, entry.col)
		if not starts[k] then number += 1 starts[k] = number end
		entry.number = starts[k]
	end
	return {id = id, title = title, subtitle = "Mixed clues / " .. #best.entries .. " words", difficulty = "Mixed",
		rows = best.rows, cols = best.cols, entries = best.entries}
end
return Generator
local DayNightCycleService = {}

local Lighting = game:GetService("Lighting")

local initialized = false

local DAY_CLOCK_TIME = 14.5
local NIGHT_CLOCK_TIME = 0
local DAY_HOLD_SECONDS = 300
local NIGHT_HOLD_SECONDS = 150

local function holdClockTime(clockTime, duration)
	Lighting.ClockTime = clockTime
	task.wait(duration)
end

function DayNightCycleService.Init()
	if initialized then
		return
	end

	initialized = true
	Lighting.ClockTime = DAY_CLOCK_TIME

	task.spawn(function()
		while true do
			holdClockTime(DAY_CLOCK_TIME, DAY_HOLD_SECONDS)
			Lighting.ClockTime = NIGHT_CLOCK_TIME
			holdClockTime(NIGHT_CLOCK_TIME, NIGHT_HOLD_SECONDS)
			Lighting.ClockTime = DAY_CLOCK_TIME
		end
	end)
end

return DayNightCycleService

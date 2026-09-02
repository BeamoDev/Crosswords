--!strict

-- Central visual and responsive tokens for the scripted Word Search interface.
-- Final fonts, icons, and artwork can be swapped here without changing screens.

local Theme = {}

Theme.Colors = table.freeze({
	Background = Color3.fromRGB(13, 14, 17),
	BackgroundRaised = Color3.fromRGB(20, 22, 27),
	Panel = Color3.fromRGB(27, 29, 35),
	PanelRaised = Color3.fromRGB(34, 37, 44),
	PanelHover = Color3.fromRGB(44, 47, 56),
	Border = Color3.fromRGB(66, 70, 80),
	BorderStrong = Color3.fromRGB(105, 110, 124),
	Text = Color3.fromRGB(250, 250, 252),
	TextMuted = Color3.fromRGB(175, 179, 190),
	TextDisabled = Color3.fromRGB(113, 117, 128),
	Accent = Color3.fromRGB(226, 35, 49),
	AccentHover = Color3.fromRGB(244, 52, 65),
	AccentDark = Color3.fromRGB(151, 22, 33),
	Success = Color3.fromRGB(61, 194, 104),
	SuccessDark = Color3.fromRGB(29, 108, 60),
	Gold = Color3.fromRGB(247, 190, 55),
	GoldDark = Color3.fromRGB(137, 91, 14),
	Info = Color3.fromRGB(82, 157, 255),
	Error = Color3.fromRGB(255, 82, 92),
	Overlay = Color3.fromRGB(2, 3, 5),
	BoardCell = Color3.fromRGB(38, 41, 49),
	BoardCellHover = Color3.fromRGB(51, 55, 65),
	BoardSelected = Color3.fromRGB(183, 27, 40),
	BoardCorrect = Color3.fromRGB(39, 158, 82),
	BoardIncorrect = Color3.fromRGB(184, 43, 55),
	Focus = Color3.fromRGB(255, 215, 82),
})

Theme.HighContrastColors = table.freeze({
	Background = Color3.fromRGB(0, 0, 0),
	BackgroundRaised = Color3.fromRGB(8, 8, 8),
	Panel = Color3.fromRGB(18, 18, 18),
	PanelRaised = Color3.fromRGB(27, 27, 27),
	PanelHover = Color3.fromRGB(45, 45, 45),
	Border = Color3.fromRGB(185, 185, 185),
	BorderStrong = Color3.fromRGB(255, 255, 255),
	Text = Color3.fromRGB(255, 255, 255),
	TextMuted = Color3.fromRGB(222, 222, 222),
	TextDisabled = Color3.fromRGB(160, 160, 160),
	Accent = Color3.fromRGB(255, 44, 62),
	AccentHover = Color3.fromRGB(255, 89, 102),
	AccentDark = Color3.fromRGB(180, 0, 21),
	Success = Color3.fromRGB(58, 255, 132),
	SuccessDark = Color3.fromRGB(0, 125, 52),
	Gold = Color3.fromRGB(255, 220, 68),
	GoldDark = Color3.fromRGB(128, 89, 0),
	Info = Color3.fromRGB(72, 177, 255),
	Error = Color3.fromRGB(255, 75, 75),
	Overlay = Color3.fromRGB(0, 0, 0),
	BoardCell = Color3.fromRGB(20, 20, 20),
	BoardCellHover = Color3.fromRGB(48, 48, 48),
	BoardSelected = Color3.fromRGB(255, 45, 62),
	BoardCorrect = Color3.fromRGB(0, 188, 82),
	BoardIncorrect = Color3.fromRGB(225, 35, 48),
	Focus = Color3.fromRGB(255, 235, 74),
})

Theme.Fonts = table.freeze({
	Display = Enum.Font.GothamBlack,
	Heading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Regular = Enum.Font.Gotham,
	Mono = Enum.Font.RobotoMono,
})

Theme.TextSizes = table.freeze({
	Display = 40,
	Title = 28,
	Heading = 21,
	Body = 17,
	Small = 14,
	Caption = 12,
	Button = 17,
	BoardLetter = 22,
})

Theme.Spacing = table.freeze({
	XXS = 4,
	XS = 8,
	S = 12,
	M = 16,
	L = 24,
	XL = 32,
	XXL = 48,
})

Theme.Radii = table.freeze({
	Small = 7,
	Medium = 12,
	Large = 18,
	Pill = 999,
})

Theme.Metrics = table.freeze({
	MinTouchTarget = 48,
	MinBoardCell = 36,
	MaxContentWidth = 1280,
	MaxModalWidth = 640,
	TopBarHeight = 72,
	PhoneTopBarHeight = 60,
	SidebarWidth = 320,
	ConsoleSidebarWidth = 380,
	SafePadding = 16,
	PhoneSafePadding = 10,
})

Theme.Motion = table.freeze({
	Fast = TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	ModalIn = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	ModalOut = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	Page = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
})

Theme.CompletedWordColors = table.freeze({
	Color3.fromRGB(56, 199, 111),
	Color3.fromRGB(75, 172, 255),
	Color3.fromRGB(247, 190, 55),
	Color3.fromRGB(190, 116, 255),
	Color3.fromRGB(255, 119, 164),
	Color3.fromRGB(58, 211, 199),
})

Theme.HighContrastCompletedWordColors = table.freeze({
	Color3.fromRGB(40, 255, 126),
	Color3.fromRGB(64, 191, 255),
	Color3.fromRGB(255, 226, 64),
	Color3.fromRGB(211, 135, 255),
	Color3.fromRGB(255, 118, 184),
	Color3.fromRGB(50, 239, 226),
})

export type LayoutName = "PhonePortrait" | "PhoneLandscape" | "Tablet" | "Desktop" | "Console"

export type Layout = {
	name: LayoutName,
	isPortrait: boolean,
	isCompact: boolean,
	isConsole: boolean,
	padding: number,
	topBarHeight: number,
	sidebarWidth: number,
	menuColumns: number,
	levelColumns: number,
	textScale: number,
}

function Theme.GetPalette(highContrast: boolean?): { [string]: Color3 }
	return if highContrast == true then Theme.HighContrastColors else Theme.Colors
end

function Theme.GetCompletedWordColors(highContrast: boolean?): { Color3 }
	return if highContrast == true then Theme.HighContrastCompletedWordColors else Theme.CompletedWordColors
end

function Theme.ResolveLayout(viewportSize: Vector2, usingGamepad: boolean?): Layout
	local width = math.max(1, viewportSize.X)
	local height = math.max(1, viewportSize.Y)
	local portrait = height > width

	-- Small touch devices can have a controller attached. Keep their viewport-safe
	-- phone/tablet geometry while still enabling gamepad focus and navigation.
	if usingGamepad == true and width >= 900 and height >= 540 then
		return {
			name = "Console",
			isPortrait = false,
			isCompact = false,
			isConsole = true,
			padding = 28,
			topBarHeight = 84,
			sidebarWidth = Theme.Metrics.ConsoleSidebarWidth,
			menuColumns = 2,
			levelColumns = 5,
			textScale = 1.12,
		}
	end

	if width < 600 and portrait then
		return {
			name = "PhonePortrait",
			isPortrait = true,
			isCompact = true,
			isConsole = false,
			padding = Theme.Metrics.PhoneSafePadding,
			topBarHeight = Theme.Metrics.PhoneTopBarHeight,
			sidebarWidth = width,
			menuColumns = 1,
			levelColumns = 3,
			textScale = 0.9,
		}
	end

	if height < 520 then
		return {
			name = "PhoneLandscape",
			isPortrait = false,
			isCompact = true,
			isConsole = false,
			padding = Theme.Metrics.PhoneSafePadding,
			topBarHeight = Theme.Metrics.PhoneTopBarHeight,
			sidebarWidth = math.clamp(width * 0.34, 240, 320),
			menuColumns = 2,
			levelColumns = 5,
			textScale = 0.9,
		}
	end

	if width < 1000 then
		return {
			name = "Tablet",
			isPortrait = portrait,
			isCompact = false,
			isConsole = false,
			padding = Theme.Metrics.SafePadding,
			topBarHeight = Theme.Metrics.TopBarHeight,
			sidebarWidth = math.clamp(width * 0.34, 280, 340),
			menuColumns = 2,
			levelColumns = 4,
			textScale = 1,
		}
	end

	return {
		name = "Desktop",
		isPortrait = portrait,
		isCompact = false,
		isConsole = false,
		padding = Theme.Metrics.SafePadding,
		topBarHeight = Theme.Metrics.TopBarHeight,
		sidebarWidth = Theme.Metrics.SidebarWidth,
		menuColumns = 2,
		levelColumns = 6,
		textScale = 1,
	}
end

function Theme.GetTextSize(role: string, layout: Layout?): number
	local base = Theme.TextSizes[role] or Theme.TextSizes.Body
	return math.max(11, math.floor(base * (layout and layout.textScale or 1) + 0.5))
end

return table.freeze(Theme)

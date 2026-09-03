--!strict

-- Central visual and responsive tokens for the scripted Word Search interface.
-- Final fonts, icons, and artwork can be swapped here without changing screens.

local Theme = {}

Theme.Colors = table.freeze({
	Background = Color3.fromRGB(5, 20, 48),
	BackgroundRaised = Color3.fromRGB(8, 35, 78),
	Panel = Color3.fromRGB(10, 48, 96),
	PanelRaised = Color3.fromRGB(15, 66, 126),
	PanelHover = Color3.fromRGB(24, 91, 164),
	Border = Color3.fromRGB(74, 166, 255),
	BorderStrong = Color3.fromRGB(129, 211, 255),
	Text = Color3.fromRGB(247, 252, 255),
	TextMuted = Color3.fromRGB(190, 225, 255),
	TextDisabled = Color3.fromRGB(116, 160, 204),
	Accent = Color3.fromRGB(21, 143, 255),
	AccentHover = Color3.fromRGB(46, 197, 255),
	AccentDark = Color3.fromRGB(5, 78, 177),
	Success = Color3.fromRGB(34, 232, 190),
	SuccessDark = Color3.fromRGB(8, 130, 124),
	Gold = Color3.fromRGB(255, 215, 72),
	GoldDark = Color3.fromRGB(167, 110, 12),
	Info = Color3.fromRGB(64, 211, 255),
	Error = Color3.fromRGB(255, 91, 124),
	Overlay = Color3.fromRGB(1, 13, 34),
	BoardCell = Color3.fromRGB(15, 71, 132),
	BoardCellHover = Color3.fromRGB(25, 112, 193),
	BoardSelected = Color3.fromRGB(19, 155, 255),
	BoardCorrect = Color3.fromRGB(18, 190, 164),
	BoardIncorrect = Color3.fromRGB(224, 58, 101),
	Focus = Color3.fromRGB(104, 229, 255),
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
	Accent = Color3.fromRGB(0, 148, 255),
	AccentHover = Color3.fromRGB(72, 211, 255),
	AccentDark = Color3.fromRGB(0, 74, 184),
	Success = Color3.fromRGB(58, 255, 132),
	SuccessDark = Color3.fromRGB(0, 125, 52),
	Gold = Color3.fromRGB(255, 220, 68),
	GoldDark = Color3.fromRGB(128, 89, 0),
	Info = Color3.fromRGB(72, 177, 255),
	Error = Color3.fromRGB(255, 75, 75),
	Overlay = Color3.fromRGB(0, 0, 0),
	BoardCell = Color3.fromRGB(20, 20, 20),
	BoardCellHover = Color3.fromRGB(48, 48, 48),
	BoardSelected = Color3.fromRGB(0, 157, 255),
	BoardCorrect = Color3.fromRGB(0, 188, 82),
	BoardIncorrect = Color3.fromRGB(225, 35, 48),
	Focus = Color3.fromRGB(93, 230, 255),
})

-- Glass-surface opacity is centralized alongside color tokens. High contrast
-- deliberately stays opaque so accessibility never depends on the 3D scene.
Theme.Transparencies = table.freeze({
	Background = 0.5,
	BackgroundRaised = 0.16,
	Panel = 0.12,
	PanelRaised = 0.08,
	PanelHover = 0.04,
	Accent = 0.02,
	AccentHover = 0,
	AccentDark = 0.32,
	Success = 0.02,
	SuccessDark = 0.1,
	Gold = 0.02,
	GoldDark = 0.1,
	Info = 0.02,
	Error = 0.02,
	Overlay = 0.24,
	BoardCell = 0.08,
	BoardCellHover = 0.03,
	BoardSelected = 0.02,
	BoardCorrect = 0.05,
	BoardIncorrect = 0.03,
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
	Color3.fromRGB(30, 232, 190),
	Color3.fromRGB(54, 176, 255),
	Color3.fromRGB(255, 215, 72),
	Color3.fromRGB(181, 123, 255),
	Color3.fromRGB(255, 108, 181),
	Color3.fromRGB(48, 226, 255),
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

function Theme.GetTransparency(token: string, highContrast: boolean?): number
	if highContrast == true then
		return 0
	end
	return Theme.Transparencies[token] or 0
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

--!strict
-->> Theme.luau
--> Colours, fonts and sizes for the whole playground, in one place so that restyling it is
--> an edit to this file rather than a hunt through every panel.

local Theme = {
	Backdrop = Color3.fromRGB(14, 15, 20),
	Window = Color3.fromRGB(29, 32, 40),
	Header = Color3.fromRGB(37, 41, 51),
	Field = Color3.fromRGB(19, 21, 27),
	Button = Color3.fromRGB(46, 51, 64),
	Stroke = Color3.fromRGB(56, 61, 75),
	Text = Color3.fromRGB(228, 231, 238),
	TextDim = Color3.fromRGB(150, 157, 172),
	TextFaint = Color3.fromRGB(98, 105, 120),
	Accent = Color3.fromRGB(94, 163, 255),
	AccentDim = Color3.fromRGB(42, 76, 124),
	Danger = Color3.fromRGB(226, 92, 92),
	DangerDim = Color3.fromRGB(96, 42, 46),

	Font = Enum.Font.BuilderSans,
	FontMedium = Enum.Font.BuilderSansMedium,
	FontBold = Enum.Font.BuilderSansBold,

	TextSize = 15,
	SmallTextSize = 13,
	RowHeight = 24,

	--- The UIScale every window is drawn at. Maintained by the entry script from the
	--- viewport size, and read by anything that has to turn screen pixels back into the
	--- unscaled pixels a window is laid out in.
	Scale = 1,
}

return Theme

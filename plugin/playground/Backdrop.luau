--!strict
-->> Backdrop.luau
--> What the effects are drawn over. Dark is the default because that is where GUI effects
--> usually live, and where Spray's emulated light reads best; Light is there to check how
--> an effect holds up on a bright panel, and None shows the 3D world behind.
-->
--> The grid is one line per 48 pixels, a rough ruler for how far a stud of speed carries a
--> particle at the default origin size.

local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

const SPACING = 48
const LINES_X = 90 -- enough for a 4K screen
const LINES_Y = 50

type Look = {
	Color: Color3?,
	Line: Color3,
	LineTransparency: number,
}

const LOOKS: { [string]: Look } = {
	Dark = { Color = Theme.Backdrop, Line = Color3.new(1, 1, 1), LineTransparency = 0.965 },
	Slate = { Color = Color3.fromRGB(46, 52, 64), Line = Color3.new(1, 1, 1), LineTransparency = 0.95 },
	Light = { Color = Color3.fromRGB(232, 235, 241), Line = Color3.new(0, 0, 0), LineTransparency = 0.94 },
	["None (3D world)"] = { Color = nil, Line = Color3.new(1, 1, 1), LineTransparency = 1 },
}

local Backdrop = {
	Options = { "Dark", "Slate", "Light", "None (3D world)" },
	Current = "Dark",
}

local frame: Frame = nil :: any
local lines: { Frame } = {}

function Backdrop.Build(Gui: GuiBase2d)
	frame = Widgets.Create("Frame", {
		Name = "Backdrop",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = Gui,
	})
	for index = 1, LINES_X do
		table.insert(lines, Widgets.Create("Frame", {
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(index * SPACING, 0),
			Size = UDim2.new(0, 1, 1, 0),
			Parent = frame,
		}))
	end
	for index = 1, LINES_Y do
		table.insert(lines, Widgets.Create("Frame", {
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, index * SPACING),
			Size = UDim2.new(1, 0, 0, 1),
			Parent = frame,
		}))
	end
	Backdrop.Set(Backdrop.Current)
end

function Backdrop.Set(Name: string)
	local look = LOOKS[Name]
	if not look then
		return
	end
	Backdrop.Current = Name
	frame.Visible = look.Color ~= nil
	if look.Color then
		frame.BackgroundColor3 = look.Color
	end
	for _, line in lines do
		line.BackgroundColor3 = look.Line
		line.BackgroundTransparency = look.LineTransparency
	end
end

return Backdrop

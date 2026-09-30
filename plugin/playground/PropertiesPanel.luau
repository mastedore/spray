--!strict
-->> PropertiesPanel.luau
--> Every ParticleEmitter property of the selected origin, grouped roughly the way Studio's
--> Properties panel groups them. An edit is written straight onto the emitter, read back
--> (the engine clamps some of them, TimeScale and Lifetime among others), and the origin
--> is marked dirty so its Spray rebuilds on the next frame.
-->
--> Properties marked with * are read by the engine but do nothing in Spray; the footnote
--> at the bottom of the panel says which and why.

local NumberSequenceField = require(script.Parent.NumberSequenceField)
local ColorSequenceField = require(script.Parent.ColorSequenceField)
local Origin = require(script.Parent.Origin)
local Presets = require(script.Parent.Presets)
local Stage = require(script.Parent.Stage)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Origin = Origin.Origin

type Item = {
	Section: string?,
	Name: string?,
	Kind: string?,
	Options: Widgets.NumberOptions?,
	Enum: Enum?,
	Range: NumberSequenceField.Range?,
	Inert: boolean?, -- no effect in Spray
}

const LAYOUT: { Item } = {
	{ Section = "Appearance" },
	{ Name = "Brightness", Kind = "Number", Options = { Min = 0, Step = 0.02 } },
	{ Name = "Color", Kind = "ColorSequence" },
	{ Name = "LightEmission", Kind = "Number", Options = { Min = 0, Max = 1, Step = 0.005 } },
	{ Name = "LightInfluence", Kind = "Number", Options = { Min = 0, Max = 1, Step = 0.005 } },
	{ Name = "Orientation", Kind = "Enum", Enum = Enum.ParticleOrientation },
	{ Name = "Size", Kind = "NumberSequence", Range = "Positive" },
	{ Name = "Squash", Kind = "NumberSequence", Range = "Symmetric" },
	{ Name = "Texture", Kind = "Texture" },
	{ Name = "Transparency", Kind = "NumberSequence", Range = "Unit" },
	{ Name = "ZOffset", Kind = "Number", Options = { Step = 0.05 } },

	{ Section = "Emission" },
	{ Name = "EmissionDirection", Kind = "Enum", Enum = Enum.NormalId },
	{ Name = "Enabled", Kind = "Bool" },
	{ Name = "Lifetime", Kind = "Range", Options = { Min = 0, Max = 20, Step = 0.01 } },
	{ Name = "Rate", Kind = "Number", Options = { Min = 0, Step = 0.25 } },
	{ Name = "Rotation", Kind = "Range", Options = { Step = 1, Decimals = 1 } },
	{ Name = "RotSpeed", Kind = "Range", Options = { Step = 1, Decimals = 1 } },
	{ Name = "Speed", Kind = "Range", Options = { Step = 0.02 } },
	{ Name = "SpreadAngle", Kind = "Vector2", Options = { Step = 0.5, Decimals = 1 } },

	{ Section = "Shape" },
	{ Name = "Shape", Kind = "Enum", Enum = Enum.ParticleEmitterShape },
	{ Name = "ShapeInOut", Kind = "Enum", Enum = Enum.ParticleEmitterShapeInOut },
	{ Name = "ShapePartial", Kind = "Number", Options = { Min = 0, Max = 1, Step = 0.005 }, Inert = true },
	{ Name = "ShapeStyle", Kind = "Enum", Enum = Enum.ParticleEmitterShapeStyle },

	{ Section = "Flipbook" },
	{ Name = "FlipbookFramerate", Kind = "Range", Options = { Min = 0, Step = 0.1 } },
	{ Name = "FlipbookLayout", Kind = "Enum", Enum = Enum.ParticleFlipbookLayout },
	{ Name = "FlipbookMode", Kind = "Enum", Enum = Enum.ParticleFlipbookMode },
	{ Name = "FlipbookStartRandom", Kind = "Bool" },

	{ Section = "Motion" },
	{ Name = "Acceleration", Kind = "Vector3", Options = { Step = 0.02 } },

	{ Section = "Particles" },
	{ Name = "Drag", Kind = "Number", Options = { Step = 0.01 } },
	{ Name = "LockedToPart", Kind = "Bool", Inert = true },
	{ Name = "TimeScale", Kind = "Number", Options = { Min = 0, Max = 1, Step = 0.005 } },
	{ Name = "VelocityInheritance", Kind = "Number", Options = { Step = 0.01 }, Inert = true },
	{ Name = "WindAffectsDrag", Kind = "Bool", Inert = true },
}

const FOOTNOTE = "* No effect in Spray. ShapePartial and VelocityInheritance are read but not used yet; "
	.. "LockedToPart is always effectively on, since particles ride along with their parent; "
	.. "there is no wind on a GUI.\n\nTip: drag a property's name (or the small x / y / min / max "
	.. "captions) sideways to scrub it. Hold Shift for fine steps."

local PropertiesPanel = {}

local target: Origin? = nil
local setters: { [string]: (any, boolean?) -> () } = {}

--- Writes one property onto the selected emitter and shows back what actually took.
local function Apply(Name: string, Value: any)
	local origin = target
	if not origin then
		return
	end
	local emitter = origin.Emitter :: any
	local ok, problem = pcall(function()
		emitter[Name] = Value
	end)
	if not ok then
		warn(`[Spray Playground] could not set {Name}: {problem}`)
	end
	local setter = setters[Name]
	if setter then
		setter(emitter[Name])
	end
	origin:MarkDirty()
end

local function TextureField(Content: Frame, Name: string)
	local thumbnail: ImageLabel = Widgets.Create("ImageLabel", {
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 24, 1, 0),
		ScaleType = Enum.ScaleType.Fit,
		Parent = Content,
	}, { Widgets.Corner(4) })
	local box = Widgets.TextField(Content, "rbxassetid://…", UDim2.new(1, -56, 1, 0), UDim2.fromOffset(28, 0))
	local presets = Widgets.Button("v", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 24, 1, 0),
		TextSize = Theme.SmallTextSize,
		Parent = Content,
	})

	box.Changed = function(text)
		local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
		-- A bare number is an asset id; anything else is taken as a full content URI.
		if string.match(trimmed, "^%d+$") then
			trimmed = "rbxassetid://" .. trimmed
		end
		Apply(Name, trimmed)
	end

	local names = {}
	for _, texture in Presets.Textures do
		table.insert(names, texture.Name)
	end
	presets.Activated:Connect(function()
		local current = target and target.Emitter.Texture
		local currentName: string? = nil
		for _, texture in Presets.Textures do
			if texture.Id == current then
				currentName = texture.Name
			end
		end
		Widgets.Popup(Content, names, currentName, function(choice)
			for _, texture in Presets.Textures do
				if texture.Name == choice then
					Apply(Name, texture.Id)
				end
			end
		end)
	end)

	setters[Name] = function(value: string)
		box.Set(value)
		thumbnail.Image = value
	end
end

local function Build(Parent: Instance, Item: Item)
	local name = Item.Name :: string
	local kind = Item.Kind

	if kind == "NumberSequence" then
		local field = NumberSequenceField.New(Parent, name, Item.Range or "Positive")
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
		return
	elseif kind == "ColorSequence" then
		local field = ColorSequenceField.New(Parent, name)
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
		return
	end

	local _, label, content = Widgets.Row(Parent, if Item.Inert then name .. "*" else name, Item.Inert)
	local options = Item.Options or {}

	if kind == "Number" then
		local field = Widgets.NumberField(content, options, label)
		field.Changed = function(value)
			if value then
				Apply(name, value)
			end
		end
		setters[name] = field.Set
	elseif kind == "Range" then
		local field = Widgets.RangeField(content, options)
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
	elseif kind == "Vector2" then
		local field = Widgets.Vector2Field(content, options)
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
	elseif kind == "Vector3" then
		local field = Widgets.Vector3Field(content, options)
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
	elseif kind == "Bool" then
		local field = Widgets.Toggle(content)
		field.Changed = function(value)
			Apply(name, value)
		end
		setters[name] = field.Set
	elseif kind == "Enum" then
		local enum = Item.Enum :: Enum
		local names = {}
		for _, item in enum:GetEnumItems() do
			table.insert(names, item.Name)
		end
		local field = Widgets.Dropdown(content, names)
		field.Changed = function(choice)
			Apply(name, (enum :: any)[choice])
		end
		setters[name] = function(value: EnumItem)
			field.Set(value.Name)
		end
	elseif kind == "Texture" then
		TextureField(content, name)
	end
end

function PropertiesPanel.Build()
	local window = Widgets.Window(
		"Particle Emitter",
		UDim2.fromOffset(12, 12),
		Vector2.zero,
		UDim2.new(0, 330, 1, -24)
	)

	local empty = Widgets.Note(window.Body, "No origin selected. Create one in the Origins panel.")
	local stack = Widgets.Stack(window.Body)

	for _, item in LAYOUT do
		if item.Section then
			Widgets.Section(stack, item.Section)
		else
			Build(stack, item)
		end
	end
	Widgets.Section(stack, "Notes")
	Widgets.Note(stack, FOOTNOTE)

	local function Bind(Selected: Origin?)
		target = Selected
		stack.Visible = Selected ~= nil
		empty.Visible = Selected == nil
		window.Title.Text = if Selected then `Particle Emitter · {Selected.Name}` else "Particle Emitter"
		if not Selected then
			return
		end
		local emitter = Selected.Emitter :: any
		for name, setter in setters do
			setter(emitter[name], true)
		end
	end

	Stage.SelectionChanged:Connect(Bind)
	Stage.ListChanged:Connect(function()
		Bind(Stage.Selected)
	end)
	Bind(Stage.Selected)
end

return PropertiesPanel

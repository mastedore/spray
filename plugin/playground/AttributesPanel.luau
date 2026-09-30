--!strict
-->> AttributesPanel.luau
--> The Spray-only knobs: every Spray* attribute Spec.luau reads off the emitter, plus the
--> seed controls, which map onto :UseRandom() and :RandomSeed().
-->
--> An attribute the emitter does not have shows Spray's default. Editing it writes the
--> attribute, which then travels with the emitter (Duplicate copies it, for instance).

local RunService = game:GetService("RunService")

local Origin = require(script.Parent.Origin)
local Stage = require(script.Parent.Stage)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Origin = Origin.Origin

type Item = {
	Section: string?,
	Name: string?,
	Kind: string?,
	Default: any,
	Options: Widgets.NumberOptions?,
	Choices: { string }?,
	Hint: string?,
}

const LABEL_SPLIT = 0.56

const LAYOUT: { Item } = {
	{ Section = "Scale" },
	{ Name = "SprayScale", Kind = "Number", Default = 1, Options = { Min = 0, Step = 0.01 } },
	{ Name = "SpraySizeScale", Kind = "Number", Default = 1, Options = { Min = 0, Step = 0.01 } },
	{ Name = "SpraySpeedScale", Kind = "Number", Default = 1, Options = { Min = 0, Step = 0.01 } },
	{
		Name = "SprayUnit",
		Kind = "Choice",
		Default = "RelativeYY",
		Choices = { "RelativeYY", "RelativeXX", "RelativeMin", "RelativeMax", "Offset" },
	},

	{ Section = "Rendering" },
	{ Name = "SprayZIndex", Kind = "Number", Default = nil, Options = { Integer = true, Step = 0.1, AllowEmpty = true, Placeholder = "parent" } },
	{ Name = "SprayMaxParticles", Kind = "Number", Default = 400, Options = { Integer = true, Min = 1, Max = 5000, Step = 1 } },
	{ Name = "SprayGlowLayers", Kind = "Number", Default = 1, Options = { Integer = true, Min = 1, Max = 8, Step = 0.05 } },
	{ Name = "SprayIgnoreClips", Kind = "Bool", Default = false },

	{ Section = "Emission" },
	{ Name = "SprayEmissionSize", Kind = "Vector2", Default = Vector2.zero, Options = { Min = 0, Step = 0.005 } },

	{ Section = "Flipbook" },
	{ Name = "SprayFlipbookGrid", Kind = "Number", Default = 4, Options = { Integer = true, Min = 1, Max = 64, Step = 0.05 } },
	{ Name = "SprayFlipbookResolution", Kind = "Number", Default = 1024, Options = { Integer = true, Min = 1, Step = 2 } },
}

const NOTES = "SprayEmissionSize is a fraction of the origin's size. SprayFlipbookGrid only applies "
	.. "with FlipbookLayout = Custom. SprayZIndex left empty follows the origin's own ZIndex."

local AttributesPanel = {}

local target: Origin? = nil
local setters: { [string]: (any) -> () } = {}

local function Read(Emitter: ParticleEmitter, Name: string, Default: any): any
	local value = Emitter:GetAttribute(Name)
	if Default == nil then
		return value
	end
	if typeof(value) == typeof(Default) then
		return value
	end
	return Default
end

local function Apply(Name: string, Value: any, Default: any)
	local origin = target
	if not origin then
		return
	end
	origin.Emitter:SetAttribute(Name, Value)
	local setter = setters[Name]
	if setter then
		setter(Read(origin.Emitter, Name, Default))
	end
	origin:MarkDirty()
end

local function Build(Parent: Instance, Item: Item)
	local name = Item.Name :: string
	local default = Item.Default
	local _, label, content = Widgets.Row(Parent, name, false, LABEL_SPLIT)
	local options = Item.Options or {}

	if Item.Kind == "Number" then
		local field = Widgets.NumberField(content, options, label)
		field.Changed = function(value)
			Apply(name, value, default)
		end
		setters[name] = field.Set
	elseif Item.Kind == "Choice" then
		local field = Widgets.Dropdown(content, Item.Choices :: { string })
		field.Changed = function(value)
			Apply(name, value, default)
		end
		setters[name] = field.Set
	elseif Item.Kind == "Bool" then
		local field = Widgets.Toggle(content)
		field.Changed = function(value)
			Apply(name, value, default)
		end
		setters[name] = field.Set
	elseif Item.Kind == "Vector2" then
		local field = Widgets.Vector2Field(content, options)
		field.Changed = function(value)
			Apply(name, value, default)
		end
		setters[name] = field.Set
	end
end

function AttributesPanel.Build()
	local window = Widgets.Window(
		"Spray",
		UDim2.new(1, -12, 0, 12),
		Vector2.new(1, 0),
		UDim2.new(0, 330, 0.55, -18)
	)

	local empty = Widgets.Note(window.Body, "No origin selected.")
	local stack = Widgets.Stack(window.Body)

	for _, item in LAYOUT do
		if item.Section then
			Widgets.Section(stack, item.Section)
		else
			Build(stack, item)
		end
	end

	-- Randomness. Not attributes: these drive :UseRandom() and :RandomSeed() on the Spray.
	Widgets.Section(stack, "Randomness")
	local _, _, eachRunContent = Widgets.Row(stack, "New seed each run", false, LABEL_SPLIT)
	local eachRun = Widgets.Toggle(eachRunContent)
	local _, seedLabel, seedContent = Widgets.Row(stack, "Seed", false, LABEL_SPLIT)
	local seed = Widgets.NumberField(seedContent, { Integer = true, Min = 0, Max = 2147483647, Step = 1 }, seedLabel, UDim2.new(1, -60, 1, 0))
	local reroll = Widgets.Button("Reroll", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 54, 1, 0),
		TextSize = Theme.SmallTextSize,
		Parent = seedContent,
	})

	eachRun.Changed = function(value)
		if target then
			target.RandomEachRun = value
		end
	end
	seed.Changed = function(value)
		if target and value then
			target:SetSeed(value)
		end
	end
	reroll.Activated:Connect(function()
		if target then
			target:SetSeed(Random.new():NextInteger(0, 2147483647))
		end
	end)

	Widgets.Section(stack, "Notes")
	Widgets.Note(stack, NOTES)

	local function Bind(Selected: Origin?)
		target = Selected
		stack.Visible = Selected ~= nil
		empty.Visible = Selected == nil
		if not Selected then
			return
		end
		for _, item in LAYOUT do
			if item.Name then
				setters[item.Name](Read(Selected.Emitter, item.Name, item.Default))
			end
		end
	end

	-- The seed changes by itself every loop when "new seed each run" is on, so these two
	-- follow the origin rather than being set once on selection.
	RunService.RenderStepped:Connect(function()
		local origin = target
		if origin then
			eachRun.Set(origin.RandomEachRun)
			seed.Set(origin.Seed)
		end
	end)

	Stage.SelectionChanged:Connect(Bind)
	Bind(Stage.Selected)
end

return AttributesPanel

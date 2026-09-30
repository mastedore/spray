--!strict
-->> PlaygroundWidget.luau
--> The playground in a Studio dock widget: the exact modules the playground game runs,
--> started with the plugin's copy of Spray and fed input from the widget.
-->
--> It's built the first time it opens and only hidden after that, so closing it keeps
--> whatever is on the stage. While it's hidden, every origin that was playing is paused
--> (a hidden widget still pays for a running Spray) and picks up where it was on return.
-->
--> This is also where emitters come IN from the place (+ New > From Studio selection).
--> They're copies: editing them on the stage never touches the originals, and Export
--> is the way back out.

local Gather = require(script.Parent.Gather)
local App = require(script.Parent.playground.App)
local Host = require(script.Parent.playground.Host)
local Input = require(script.Parent.playground.Input)
local Origin = require(script.Parent.playground.Origin)
local Stage = require(script.Parent.playground.Stage)

type Origin = Origin.Origin

const WIDGET_ID = "SprayPlayground"
--- Origins the playground accepts, the same range the Size field in the Origins panel has.
const MINIMUM_SIZE = 4
const MAXIMUM_SIZE = 2000
--- Frames to wait for a freshly shown widget to be given a size before building anyway.
const SIZE_WAIT = 60

local PlaygroundWidget = {}

local widget: DockWidgetPluginGui = nil :: any
local cursor: (string) -> () = function() end
local built = false
local suspended: { Origin } = {}

--- The four layers App wants, as Frames inside one surface that covers the widget and is
--- where input is read from. Being every layer's ancestor, the surface hears a press
--- wherever it lands.
---
--- One thing differs from the game: SprayIgnoreClips hoists a pool up to the nearest
--- LayerCollector, which here is the widget, outside the surface, so an origin with it on
--- draws over the panels too.
local function Build()
	local function Layer(Name: string, ZIndex: number, Parent: Instance): Frame
		local frame = Instance.new("Frame")
		frame.Name = Name
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = ZIndex
		frame.Parent = Parent
		return frame
	end

	local surface = Layer("Surface", 1, widget)
	Input.UseWidget(widget, surface, cursor)

	-- A widget that was just shown can still be zero sized for a moment, and windows laid
	-- out against zero would all be pushed to one corner.
	local waited = 0
	while widget.AbsoluteSize.X <= 0 and waited < SIZE_WAIT do
		task.wait()
		waited += 1
	end

	App.Start({
		Backdrop = Layer("Backdrop", 1, surface),
		Stage = Layer("Stage", 2, surface),
		Panels = Layer("Panels", 3, surface),
		Popups = Layer("Popups", 4, surface),
	}, function()
		return widget.AbsoluteSize
	end, widget:GetPropertyChangedSignal("AbsoluteSize"))
end

local function Sync()
	if widget.Enabled then
		if not built then
			built = true
			Build()
		end
		for _, origin in suspended do
			if not origin.Destroyed then
				origin:Play()
			end
		end
		table.clear(suspended)
	else
		for _, origin in Stage.Origins do
			if origin.Playing then
				origin:Pause()
				table.insert(suspended, origin)
			end
		end
	end
end

--- Copies of every emitter at or under the Studio selection, each sized like the GuiObject
--- it was drawn in so it looks the same on the stage.
local function Import(): { Host.Imported }
	local found: { Host.Imported } = {}
	for _, emitter in Gather.Selected() do
		local copy = emitter:Clone()
		if not copy then
			warn(`[Spray] {emitter:GetFullName()} can't be copied (Archivable is off), skipped.`)
			continue
		end
		local host = emitter:FindFirstAncestorWhichIsA("GuiObject")
		local size: Vector2? = nil
		if host and host.AbsoluteSize.X > 0 and host.AbsoluteSize.Y > 0 then
			local measured = host.AbsoluteSize
			size = Vector2.new(
				math.clamp(math.round(measured.X), MINIMUM_SIZE, MAXIMUM_SIZE),
				math.clamp(math.round(measured.Y), MINIMUM_SIZE, MAXIMUM_SIZE)
			)
		end
		table.insert(found, { Emitter = copy, Name = emitter.Name, Size = size })
	end
	return found
end

function PlaygroundWidget.Setup(Plugin: Plugin, Toggled: (Open: boolean) -> ())
	local mouse = Plugin:GetMouse()
	cursor = function(Icon)
		mouse.Icon = Icon
	end
	Host.Import = Import

	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 1280, 800, 720, 480)
	widget = Plugin:CreateDockWidgetPluginGuiAsync(WIDGET_ID, info)
	widget.Name = WIDGET_ID
	widget.Title = "Spray Playground"
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		Sync()
		Toggled(widget.Enabled)
	end)
	-- Studio reopens a widget that was open when it last closed.
	if widget.Enabled then
		task.spawn(Sync)
	end
end

function PlaygroundWidget.Toggle()
	widget.Enabled = not widget.Enabled
end

function PlaygroundWidget.IsOpen(): boolean
	return widget.Enabled
end

return PlaygroundWidget

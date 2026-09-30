--!strict
-->> App.luau
--> Puts the playground together: the four layers, the windows, the first origin and the
--> per-frame step. Both hosts start it the same way; what differs is only what they pass
--> in (and what they put in Host.luau first).
-->
--> Layering, back to front: backdrop, stage, panels, popups. In the game each layer is a
--> ScreenGui of its own. A Studio widget can't nest ScreenGuis, so there they are Frames
--> ordered by ZIndex, and nothing below cares which.

local RunService = game:GetService("RunService")

local AttributesPanel = require(script.Parent.AttributesPanel)
local Backdrop = require(script.Parent.Backdrop)
local OriginsPanel = require(script.Parent.OriginsPanel)
local PlaybackPanel = require(script.Parent.PlaybackPanel)
local Presets = require(script.Parent.Presets)
local PropertiesPanel = require(script.Parent.PropertiesPanel)
local Stage = require(script.Parent.Stage)
local Widgets = require(script.Parent.Widgets)

--- The screen size the panels are laid out for. Smaller screens scale them down, never
--- below MINIMUM_SCALE, past which the text stops being readable.
const REFERENCE = Vector2.new(1440, 860)
const MINIMUM_SCALE = 0.6

export type Layers = {
	Backdrop: GuiBase2d,
	Stage: GuiBase2d,
	Panels: GuiBase2d,
	Popups: GuiBase2d,
}

local App = {}

--- `Measure` gives the size the panels have to fit in, and `Resized` fires when it changes.
function App.Start(Layers: Layers, Measure: () -> Vector2, Resized: RBXScriptSignal)
	local function Rescale()
		local space = Measure()
		local scale = math.min(space.X / REFERENCE.X, space.Y / REFERENCE.Y)
		Widgets.Rescale(math.clamp(scale, MINIMUM_SCALE, 1))
	end

	Backdrop.Build(Layers.Backdrop)
	Stage.Build(Layers.Stage)
	Widgets.Setup(Layers.Panels, Layers.Popups)

	-- Before the windows exist, so they are built at the right scale from the start.
	Rescale()
	Resized:Connect(Rescale)

	PropertiesPanel.Build()
	AttributesPanel.Build()
	PlaybackPanel.Build()
	OriginsPanel.Build()

	-- Something on screen from the first frame, so whoever opens it sees what this is about.
	Stage.Add(Presets.Build(Presets.Default), Presets.Default)

	RunService.Heartbeat:Connect(Stage.Step)
end

return App

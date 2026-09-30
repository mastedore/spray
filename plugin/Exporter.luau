--!strict
-->> Exporter.luau
--> Copies playground origins out into the open place, so an effect designed on the stage
--> ends up as the Instances you'd actually ship: its ParticleEmitter with every edit made
--> to it (Spray attributes and BurstCount included), inside a Frame called OriginVFX the
--> size the origin had, inside a throwaway ScreenGui in StarterGui.
-->
--> The Frame is the part worth keeping. It's what one stud is measured against (its height,
--> with the default SprayUnit), so the emitter alone, moved into a frame of another size,
--> plays bigger or smaller than it did on the stage. Move the whole OriginVFX frame into
--> your UI and it plays as designed.
-->
--> Several origins go into the same ScreenGui, one frame each (OriginVFX_<Name>, so they
--> can be told apart), keeping where they sat around the middle of the stage and which
--> one was drawn in front.
-->
--> With the code option there is also a PlayVFX LocalScript in the ScreenGui, written by
--> Snippet.luau. It runs in a playtest as it is, which is the quickest way to check the
--> export matches the playground.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local StarterGui = game:GetService("StarterGui")

local Origin = require(script.Parent.playground.Origin)
local Snippet = require(script.Parent.Snippet)

type Origin = Origin.Origin

const GUI_NAME = "SprayExport"
const FRAME_NAME = "OriginVFX"
const SCRIPT_NAME = "PlayVFX"

local Exporter = {}

local function FreeName(Parent: Instance, Base: string): string
	if not Parent:FindFirstChild(Base) then
		return Base
	end
	local index = 2
	while Parent:FindFirstChild(`{Base}{index}`) do
		index += 1
	end
	return `{Base}{index}`
end

--- Whether `Name` already means something on `Object`, a property or a method. A child
--- called that couldn't be reached as `Object.Name` in the generated code.
local function Shadowed(Object: Instance, Name: string): boolean
	local ok, value = pcall(function()
		return (Object :: any)[Name]
	end)
	return ok and value ~= nil
end

local function SprayInstalled(): boolean
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	return packages ~= nil and packages:FindFirstChild("Spray") ~= nil
end

function Exporter.Export(Plugin: Plugin, Origins: { Origin }, WithSnippet: boolean): ScreenGui
	-- Back to front, so each frame's ZIndex keeps the order they were drawn in.
	local ordered = table.clone(Origins)
	table.sort(ordered, function(A, B)
		return A.Frame.ZIndex < B.Frame.ZIndex
	end)

	local recording = ChangeHistoryService:TryBeginRecording("Export Spray VFX")

	local gui = Instance.new("ScreenGui")
	gui.Name = FreeName(StarterGui, GUI_NAME)
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local layers: { Snippet.Layer } = {}
	local taken: { [string]: boolean } = {}
	for index, origin in ordered do
		local emitterName = Snippet.PascalCase(origin.Name)
		local frameName = FRAME_NAME
		if #ordered > 1 then
			frameName = `{FRAME_NAME}_{emitterName}`
			local base = frameName
			local suffix = 2
			while taken[frameName] do
				frameName = `{base}{suffix}`
				suffix += 1
			end
		end
		taken[frameName] = true

		local frame = Instance.new("Frame")
		frame.Name = frameName
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = origin.Frame.Position
		frame.Size = origin.Frame.Size
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = index
		frame.Parent = gui

		if Shadowed(frame, emitterName) then
			emitterName ..= "VFX"
		end
		local emitter = origin.Emitter:Clone()
		emitter.Name = emitterName
		emitter.Parent = frame

		table.insert(layers, { Origin = origin, Frame = frameName, Emitter = emitterName })
	end

	local code: LocalScript? = nil
	if WithSnippet then
		local generated = Instance.new("LocalScript")
		generated.Name = SCRIPT_NAME
		generated.Source = Snippet.Generate(layers)
		generated.Parent = gui
		code = generated
	end

	gui.Parent = StarterGui
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end

	Selection:Set({ gui })
	local count = #ordered
	print(`[Spray] Exported {count} origin{if count == 1 then "" else "s"} to StarterGui.{gui.Name}. `
		.. "It's selected: press Preview to watch it play.")
	if code then
		if not SprayInstalled() then
			warn("[Spray] PlayVFX requires ReplicatedStorage.Packages.Spray, which isn't in this place yet. Press Import first.")
		end
		Plugin:OpenScript(code)
	end
	return gui
end

return Exporter

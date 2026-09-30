-->> Helpers.luau
--> Shared setup for the specs: a GUI host to draw into and an emitter with every random
--> range collapsed, so the expected numbers can be worked out by hand.
-->
--> The emitter uses SprayUnit = Offset (one stud is one pixel). That keeps every drawn
--> position and size independent of how big the host happens to be on screen, which is
--> not something a test running on the server can rely on.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Helpers = {}

--- The Spray ModuleScript itself. Specs require it, or its children, from here.
Helpers.Package = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Spray")

--- A ScreenGui with a 200x100 Frame in it, somewhere inside the DataModel - Spray will not
--- draw into a parent that is off the tree. Destroy the ScreenGui when done.
function Helpers.Host(): (ScreenGui, Frame)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SprayTestHost"
	local frame = Instance.new("Frame")
	frame.Name = "Host"
	frame.Size = UDim2.fromOffset(200, 100)
	frame.Parent = gui

	-- Studio's edit mode can have a LocalPlayer with no PlayerGui, so look rather than wait.
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	gui.Parent = playerGui or game:GetService("StarterGui")
	return gui, frame
end

--- A point emitter firing straight up at 100 px/s, 10 px particles that live exactly one
--- second, no drag, no gravity, no spread, no rotation. `Properties` and `Attributes`
--- override any of it.
function Helpers.Emitter(Properties: { [string]: any }?, Attributes: { [string]: any }?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Probe"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(1)
	emitter.Speed = NumberRange.new(100)
	emitter.SpreadAngle = Vector2.zero
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Size = NumberSequence.new(10)
	emitter.Squash = NumberSequence.new(0)
	emitter.Transparency = NumberSequence.new(0)
	emitter.Rotation = NumberRange.new(0)
	emitter.RotSpeed = NumberRange.new(0)
	emitter.Acceleration = Vector3.zero
	emitter.Drag = 0
	emitter.Brightness = 1
	emitter.LightEmission = 0
	emitter.LightInfluence = 0
	emitter:SetAttribute("SprayUnit", "Offset")

	for name, value in Properties or {} do
		(emitter :: any)[name] = value
	end
	for name, value in Attributes or {} do
		emitter:SetAttribute(name, value)
	end
	return emitter
end

--- Every particle currently on screen under `Host`.
function Helpers.Visible(Host: Instance): { ImageLabel }
	local found = {}
	for _, node in Host:GetDescendants() do
		if node:IsA("ImageLabel") and node.Name == "Particle" and node.Visible then
			table.insert(found, node)
		end
	end
	return found
end

--- The on-screen particles as a sorted list of "x,y,w,h" strings, rounded to a hundredth
--- of a pixel: two draws of the same moment compare equal, whatever slot each particle
--- happened to land in.
function Helpers.Picture(Host: Instance): { string }
	local picture = {}
	for _, label in Helpers.Visible(Host) do
		local position, size = label.Position, label.Size
		table.insert(picture, string.format(
			"%.2f,%.2f,%.2f,%.2f",
			position.X.Offset, position.Y.Offset, size.X.Offset, size.Y.Offset
		))
	end
	table.sort(picture)
	return picture
end

function Helpers.Same(A: { string }, B: { string }): boolean
	if #A ~= #B then
		return false
	end
	for index, value in A do
		if B[index] ~= value then
			return false
		end
	end
	return true
end

return Helpers

--!strict
-->> Stage.luau
--> The canvas the origins live on, and the one place that knows which of them is selected.
--> Panels never hold on to an origin for longer than a SelectionChanged; they ask here.
-->
--> Picking is done here too, from Input.Began rather than from each origin's own
--> InputBegan: overlapping origins would all hear the same click, and the stage is the one
--> that knows which of them is on top.

local Drag = require(script.Parent.Drag)
local Input = require(script.Parent.Input)
local Origin = require(script.Parent.Origin)
local Signal = require(script.Parent.Signal)
local Widgets = require(script.Parent.Widgets)

type Origin = Origin.Origin

const DEFAULT_SIZE = Vector2.new(120, 120)
const CASCADE = 40
--- Small origins still get a grabbable area at least this big.
const MINIMUM_GRAB = 32

local Stage = {
	Origins = {} :: { Origin },
	Selected = nil :: Origin?,
	Outlines = true,
	--- Fires with the newly selected origin, or nil when the last one was deleted.
	SelectionChanged = Signal.New(),
	--- Fires when origins are added, removed or renamed.
	ListChanged = Signal.New(),
}

local gui: GuiBase2d = nil :: any
local topZ = 1

local function Raise(Target: Origin)
	topZ += 1
	Target.Frame.ZIndex = topZ
	-- Kept in draw order too, so picking can walk the list from the top down.
	local index = table.find(Stage.Origins, Target)
	if index then
		table.remove(Stage.Origins, index)
		table.insert(Stage.Origins, Target)
	end
end

local function Grabs(Target: Origin, Point: Vector2): boolean
	local frame = Target.Frame
	local size = frame.AbsoluteSize
	local centre = frame.AbsolutePosition + size * 0.5
	local half = Vector2.new(math.max(size.X, MINIMUM_GRAB), math.max(size.Y, MINIMUM_GRAB)) * 0.5
	local offset = Point - centre
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y
end

--- The selected origin wins when it is under the pointer, so it can always be dragged
--- even from underneath another one; otherwise the topmost.
local function Pick(Point: Vector2): Origin?
	local selected = Stage.Selected
	if selected and Grabs(selected, Point) then
		return selected
	end
	for index = #Stage.Origins, 1, -1 do
		local candidate = Stage.Origins[index]
		if Grabs(candidate, Point) then
			return candidate
		end
	end
	return nil
end

--- Keeps an origin's centre on screen.
local function Keep(Target: Origin)
	local frame = Target.Frame
	local bounds = gui.AbsoluteSize
	local centre = frame.AbsolutePosition + frame.AbsoluteSize * 0.5 - gui.AbsolutePosition
	local clamped = Vector2.new(math.clamp(centre.X, 0, bounds.X), math.clamp(centre.Y, 0, bounds.Y))
	if clamped ~= centre then
		Target:MoveTo(frame.Position + UDim2.fromOffset(clamped.X - centre.X, clamped.Y - centre.Y))
	end
end

local function UniqueName(Base: string): string
	local taken: { [string]: boolean } = {}
	for _, origin in Stage.Origins do
		taken[origin.Name] = true
	end
	if not taken[Base] then
		return Base
	end
	local index = 2
	while taken[`{Base} {index}`] do
		index += 1
	end
	return `{Base} {index}`
end

function Stage.Build(Gui: GuiBase2d)
	gui = Gui

	Input.Began:Connect(function(input: InputObject, processed: boolean, root: Instance?)
		if processed or not Drag.IsPress(input) or not Input.Within(root, gui) then
			return
		end
		local point = Drag.Point(input)
		if Widgets.OverUi(point) then
			return
		end
		local target = Pick(point)
		if not target then
			return
		end

		Stage.Select(target)
		local start = target.Frame.Position
		Drag.Follow(input, function(_, delta)
			if target.Destroyed then
				return
			end
			target:MoveTo(start + UDim2.fromOffset(delta.X, delta.Y))
			Keep(target)
		end)
	end)
end

function Stage.Add(Emitter: ParticleEmitter, Name: string, Position: UDim2?, Size: Vector2?): Origin
	local cascade = (#Stage.Origins % 6) * CASCADE
	local origin = Origin.New(
		Emitter,
		UniqueName(Name),
		gui,
		Position or UDim2.new(0.5, cascade, 0.5, cascade),
		Size or DEFAULT_SIZE
	)
	origin:SetOutline(Stage.Outlines)
	table.insert(Stage.Origins, origin)
	Stage.ListChanged:Fire()
	Stage.Select(origin)
	return origin
end

--- A copy of `Source` with its emitter, attributes and transport settings, offset a little
--- so it does not sit exactly on top.
function Stage.Duplicate(Source: Origin): Origin
	local size = Source.Frame.Size
	local copy = Stage.Add(
		Source.Emitter:Clone(),
		Source.Name,
		Source.Frame.Position + UDim2.fromOffset(CASCADE, CASCADE),
		Vector2.new(size.X.Offset, size.Y.Offset)
	)
	copy.Loop = Source.Loop
	copy.Duration = Source.Duration
	copy.EmitCount = Source.EmitCount
	copy.RandomEachRun = Source.RandomEachRun
	copy.Seed = Source.Seed
	copy:Restart()
	Keep(copy)
	return copy
end

function Stage.Remove(Target: Origin)
	local index = table.find(Stage.Origins, Target)
	if not index then
		return
	end
	table.remove(Stage.Origins, index)

	local wasSelected = Stage.Selected == Target
	if wasSelected then
		Stage.Selected = nil
	end
	Target:Destroy()
	Stage.ListChanged:Fire()

	if wasSelected then
		local nextOrigin = Stage.Origins[#Stage.Origins]
		if nextOrigin then
			Stage.Select(nextOrigin)
		else
			Stage.SelectionChanged:Fire(nil)
		end
	end
end

function Stage.Select(Target: Origin?)
	if Stage.Selected == Target then
		return
	end
	local previous = Stage.Selected
	if previous then
		previous:SetSelected(false)
	end
	Stage.Selected = Target
	if Target then
		Target:SetSelected(true)
		Raise(Target)
	end
	Stage.SelectionChanged:Fire(Target)
end

function Stage.Rename(Target: Origin, Name: string)
	local trimmed = string.match(Name, "^%s*(.-)%s*$") or ""
	if trimmed == "" or trimmed == Target.Name then
		return
	end
	Target:Rename(UniqueName(trimmed))
	Stage.ListChanged:Fire()
end

function Stage.SetOutlines(Visible: boolean)
	Stage.Outlines = Visible
	for _, origin in Stage.Origins do
		origin:SetOutline(Visible)
	end
end

--- Runs every origin's transport. Every origin updates, not just the selected one, which is
--- what keeps a looping origin looping after you click away from it.
function Stage.Step()
	local now = os.clock()
	for _, origin in table.clone(Stage.Origins) do
		origin:Update(now)
	end
end

return Stage

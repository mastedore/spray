--!strict
-->> Origin.luau
--> An origin is one draggable Frame on the stage, the ParticleEmitter inside it, and the
--> Spray drawing that emitter. It also owns the emitter's transport: whether it is playing,
--> whether it loops, how long one run lasts, and which bursts went off during this run.
-->
--> WHY THE BURSTS ARE REMEMBERED. A Spray only sees a property change after :Cleanup(),
--> and :Cleanup() throws the timeline away along with the snapshot. So an edit is applied
--> by rebuilding and replaying: same seed, same bursts at the same times, clock put back
--> where it was. Because Spray evaluates everything from the clock, that lands on exactly
--> the frame you were looking at - which is what lets a property be dragged around, playing
--> or paused, without the particles reshuffling under the cursor.
-->
--> For the same reason the playground rolls the seed itself (one per run) and hands it to
--> Spray with :UseRandom(false) + :RandomSeed(), instead of leaving Spray to reseed on its
--> own. Left to Spray, every rebuild would be a new roll and every edit a new effect.
-->
--> WRAPPED ORIGINS. The plugin previews emitters that live in the open place, where they
--> can't be moved into a box on the stage. Origin.Wrap gives those the same transport and
--> leaves them where they are: no frame of its own, nothing of the host destroyed, and a
--> rebuild whenever the emitter changes, so edits made in Studio's Properties panel show
--> up live.

local Host = require(script.Parent.Host)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Effect = Host.Effect

--- Breathing room after the longest-lived particle, so a looping burst reads as a burst
--- repeating rather than as a stream. Same value Spray's Preview uses.
const LOOP_GAP = 0.45
--- A stream has no natural end, so its auto duration is long enough to reach steady state.
const STREAM_MINIMUM = 4
--- Rebuilds are coalesced to this rate. Dragging a slider asks for one every frame, and a
--- rebuild recreates the whole pool.
const REFRESH_INTERVAL = 1 / 30
--- Spray keeps this many bursts of history, so there is no point remembering more.
const BURST_HISTORY = 64
const DEFAULT_EMIT = 20

local random = Random.new()

export type Burst = {
	Time: number,
	Count: number,
}

local Origin = {}
Origin.__index = Origin

export type Origin = typeof(setmetatable({} :: {
	Name: string,
	--- The box on the stage, or for a wrapped origin the GuiObject its emitter draws in.
	Frame: GuiObject,
	Emitter: ParticleEmitter,
	Effect: Effect,
	Wrapped: boolean,

	Playing: boolean,
	Loop: boolean,
	Duration: number?, -- nil means automatic
	EmitCount: number,
	RandomEachRun: boolean,
	Seed: number,
	Bursts: { Burst },
	Revision: number, -- bumped whenever the burst list changes, for the timeline ticks
	Destroyed: boolean,

	_dirty: boolean,
	_lastRefresh: number,
	_label: TextLabel?, -- the stage decorations, which a wrapped origin doesn't have
	_outline: UIStroke?,
	_dot: Frame?,
	_selected: boolean,
	_outlines: boolean,
	_connections: { RBXScriptConnection },
}, Origin))

-- -- Reading Spray's private state ---------------------------------------------

--- Spray has no getter for its clock yet, so the playground reads the field. This and
--- LiveCount below are the only two places that reach past the public API.
local function ClockOf(Effect: Effect): number
	return (Effect :: any)._clock or 0
end

-- -- Construction --------------------------------------------------------------

--- The fields both kinds of origin share. Not started yet: the constructors call Restart.
local function Construct(Emitter: ParticleEmitter, Name: string, Frame: GuiObject, Wrapped: boolean): Origin
	local burstCount = Emitter:GetAttribute("BurstCount")

	return setmetatable({
		Name = Name,
		Frame = Frame,
		Emitter = Emitter,
		Effect = Host.Library().New(Emitter),
		Wrapped = Wrapped,

		Playing = false,
		Loop = true,
		Duration = nil,
		EmitCount = if typeof(burstCount) == "number" and burstCount > 0 then burstCount else DEFAULT_EMIT,
		RandomEachRun = true,
		Seed = random:NextInteger(0, 2147483647),
		Bursts = {},
		Revision = 0,
		Destroyed = false,

		_dirty = false,
		_lastRefresh = 0,
		_label = nil,
		_outline = nil,
		_dot = nil,
		_selected = false,
		_outlines = true,
		_connections = {},
	}, Origin)
end

function Origin.New(Emitter: ParticleEmitter, Name: string, Parent: Instance, Position: UDim2, Size: Vector2): Origin
	local frame: Frame = Widgets.Create("Frame", {
		Name = Name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = Position,
		Size = UDim2.fromOffset(Size.X, Size.Y),
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.97,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, { Widgets.Corner(4) })
	local outline: UIStroke = Widgets.Create("UIStroke", {
		Color = Theme.TextFaint,
		Thickness = 1,
		Transparency = 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	local label = Widgets.Label({
		Name = "Label",
		Text = Name,
		TextSize = Theme.SmallTextSize,
		TextColor3 = Theme.TextDim,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 0, -3),
		Size = UDim2.new(1, 60, 0, 16),
		Parent = frame,
	})
	local dot: Frame = Widgets.Create("Frame", {
		Name = "Centre",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = Theme.TextDim,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Widgets.Corner(3) })

	Emitter.Parent = frame
	frame.Parent = Parent

	local self = Construct(Emitter, Name, frame, false)
	self._label = label
	self._outline = outline
	self._dot = dot
	self:Restart()
	return self
end

--- An origin for an emitter that stays where it is, drawn in the GuiObject it already
--- sits under. See WRAPPED ORIGINS in the header.
function Origin.Wrap(Emitter: ParticleEmitter, Name: string): Origin
	local host = Emitter:FindFirstAncestorWhichIsA("GuiObject")
	assert(host, `Playground: {Emitter:GetFullName()} is not inside a GuiObject`)

	local self = Construct(Emitter, Name, host, true)
	local function Edited()
		self:MarkDirty()
	end
	table.insert(self._connections, Emitter.Changed:Connect(Edited))
	table.insert(self._connections, Emitter.AttributeChanged:Connect(Edited))
	-- One stud is the host's height, read every frame; paused, nothing else would redraw.
	table.insert(self._connections, host:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if not self.Playing and not self._dirty then
			self:Redraw()
		end
	end))

	self:Restart()
	return self
end

-- -- Queries -------------------------------------------------------------------

function Origin.Clock(self: Origin): number
	return ClockOf(self.Effect)
end

--- How many particle slots are drawing right now.
function Origin.LiveCount(self: Origin): number
	local renderer = (self.Effect :: any)._renderer
	if not renderer then
		return 0
	end
	local count = 0
	for _ in renderer.Active do
		count += 1
	end
	return count
end

function Origin.AutoDuration(self: Origin): number
	local emitter = self.Emitter
	local lifetime = math.max(emitter.Lifetime.Max, 0.05)
	if emitter.Enabled and emitter.Rate > 0 then
		return math.max(STREAM_MINIMUM, lifetime * 2 + LOOP_GAP)
	end
	return lifetime + LOOP_GAP
end

function Origin.GetDuration(self: Origin): number
	return self.Duration or self:AutoDuration()
end

--- The burst fired at the start of every run. Kept as the BurstCount attribute, the same
--- one Spray's Preview reads, so an emitter carries it wherever it is copied.
function Origin.GetBurstCount(self: Origin): number
	local value = self.Emitter:GetAttribute("BurstCount")
	if typeof(value) == "number" then
		return math.max(0, math.floor(value))
	end
	return 0
end

function Origin.SetBurstCount(self: Origin, Count: number)
	self.Emitter:SetAttribute("BurstCount", math.max(0, math.floor(Count)))
end

-- -- Transport -----------------------------------------------------------------

local function Touch(self: Origin)
	self.Revision += 1
end

--- Starts a new run from zero: fresh seed if asked for, the start burst, and playing -
--- unless `KeepPaused` is set and it was paused, which is what the Restart button wants.
function Origin.Restart(self: Origin, KeepPaused: boolean?)
	local resume = not (KeepPaused and not self.Playing)
	if self.RandomEachRun then
		self.Seed = random:NextInteger(0, 2147483647)
	end

	local effect = self.Effect
	effect:UseRandom(false)
	effect:RandomSeed(self.Seed)

	-- :Emit() on a paused Spray rewinds to zero before emitting. Pausing first makes that
	-- the path taken even when it is mid-run, and Emit(0) still does the rewind when there
	-- is no start burst - it just adds nothing.
	effect:Pause()
	table.clear(self.Bursts)
	local count = self:GetBurstCount()
	effect:Emit(count)
	if count > 0 then
		table.insert(self.Bursts, { Time = 0, Count = count })
	end
	effect:SetTime(0)

	self.Playing = resume
	if not resume then
		effect:Pause()
	end
	Touch(self)
end

function Origin.Play(self: Origin)
	if self.Playing then
		return
	end
	-- At the end of a run that did not loop, play means play it again.
	if self:Clock() >= self:GetDuration() - 1e-3 then
		self:Restart()
		return
	end
	self.Effect:Resume()
	self.Playing = true
end

function Origin.Pause(self: Origin)
	if not self.Playing then
		return
	end
	self.Effect:Pause()
	self.Playing = false
end

function Origin.Toggle(self: Origin)
	if self.Playing then
		self:Pause()
	else
		self:Play()
	end
end

function Origin.Seek(self: Origin, Time: number)
	self.Effect:SetTime(math.clamp(Time, 0, self:GetDuration()))
end

--- Nudges the clock, pausing first: stepping frame by frame only makes sense held still.
function Origin.Step(self: Origin, Delta: number)
	self:Pause()
	self.Effect:Forward(Delta)
	local duration = self:GetDuration()
	if self:Clock() > duration then
		self.Effect:SetTime(duration)
	end
end

--- Fires `Count` particles now, on top of whatever is in flight. Emitting into a paused or
--- finished run starts a new one first, the same rule Spray's own :Emit() follows.
function Origin.Emit(self: Origin, Count: number)
	if Count <= 0 then
		return
	end
	if not self.Playing then
		self:Restart()
	end
	table.insert(self.Bursts, { Time = self:Clock(), Count = Count })
	if #self.Bursts > BURST_HISTORY then
		table.remove(self.Bursts, 1)
	end
	self.Effect:Emit(Count)
	Touch(self)
end

-- -- Rebuilding ----------------------------------------------------------------

--- Asks for a rebuild on the next update. Called after every property or attribute edit.
function Origin.MarkDirty(self: Origin)
	self._dirty = true
end

function Origin.SetSeed(self: Origin, Seed: number)
	self.Seed = math.floor(Seed) % 2147483648
	self:MarkDirty()
end

--- Rebuilds the Spray so it rereads the emitter, then replays this run's bursts and puts
--- the clock back. See the header for why that lands on the same frame.
function Origin.Refresh(self: Origin)
	self._dirty = false
	-- A wrapped emitter can be dragged out of the UI in Explorer. Rebuilding then would
	-- throw (a Spray needs a GuiObject to draw in); whoever owns the origin drops it.
	if not self.Emitter:FindFirstAncestorWhichIsA("GuiObject") then
		return
	end

	local effect = self.Effect
	local clock = self:Clock()

	effect:Cleanup()
	effect:UseRandom(false)
	effect:RandomSeed(self.Seed)

	-- Emit on a paused Spray (which :Cleanup() leaves it) rewinds and starts playing, and
	-- from then on emits stack at whatever time SetTime put the clock on.
	local bursts = self.Bursts
	if #bursts == 0 or bursts[1].Time > 0 then
		effect:Emit(0)
	end
	for _, burst in bursts do
		effect:SetTime(burst.Time)
		effect:Emit(burst.Count)
	end

	effect:SetTime(clock)
	if not self.Playing then
		effect:Pause()
	end
end

--- Draws the current frame again without moving the clock. Needed while paused, when
--- nothing else would redraw - after a resize, or dragging an origin whose pool was
--- hoisted out of it by SprayIgnoreClips.
function Origin.Redraw(self: Origin)
	self.Effect:Forward(0)
end

--- Called once a frame by the stage: applies pending edits and handles the end of a run.
function Origin.Update(self: Origin, Now: number)
	if self._dirty and Now - self._lastRefresh >= REFRESH_INTERVAL then
		self._lastRefresh = Now
		self:Refresh()
	end

	if not self.Playing then
		return
	end
	local duration = self:GetDuration()
	if self:Clock() < duration then
		return
	end
	if self.Loop then
		self:Restart()
	else
		self.Effect:Pause()
		self.Effect:SetTime(duration)
		self.Playing = false
	end
end

-- -- Presentation --------------------------------------------------------------

local function Restyle(self: Origin)
	local outline, label, dot = self._outline, self._label, self._dot
	if not (outline and label and dot) then
		return -- wrapped, nothing of ours to style
	end
	local selected = self._selected
	local visible = self._outlines or selected
	outline.Enabled = visible
	outline.Color = if selected then Theme.Accent else Theme.TextFaint
	outline.Thickness = if selected then 2 else 1
	outline.Transparency = if selected then 0 else 0.4
	self.Frame.BackgroundTransparency = if visible then (if selected then 0.93 else 0.97) else 1
	label.Visible = visible
	label.TextColor3 = if selected then Theme.Accent else Theme.TextDim
	dot.Visible = visible
end

function Origin.SetSelected(self: Origin, Selected: boolean)
	self._selected = Selected
	Restyle(self)
end

--- Whether unselected origins show their box. The selected one always does.
function Origin.SetOutline(self: Origin, Visible: boolean)
	self._outlines = Visible
	Restyle(self)
end

function Origin.Rename(self: Origin, Name: string)
	self.Name = Name
	if self.Wrapped then
		return
	end
	self.Frame.Name = Name
	local label = self._label
	if label then
		label.Text = Name
	end
end

function Origin.MoveTo(self: Origin, Position: UDim2)
	self.Frame.Position = Position
	if not self.Playing then
		self:Redraw()
	end
end

function Origin.Resize(self: Origin, Size: Vector2)
	self.Frame.Size = UDim2.fromOffset(Size.X, Size.Y)
	-- One stud is the parent's height, read every frame, so there is nothing to rebuild;
	-- a paused origin just needs drawing again at the new scale.
	if not self.Playing then
		self:Redraw()
	end
end

function Origin.Destroy(self: Origin)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self.Effect:Destroy()
	-- A wrapped origin's frame belongs to someone else's UI.
	if not self.Wrapped then
		self.Frame:Destroy()
	end
end

return Origin

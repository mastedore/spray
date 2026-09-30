--!strict
--!native
-->> Spray.luau
--> ParticleEmitters for GUI. Point it at a ParticleEmitter that lives inside a GuiObject
--> and it plays that emitter's effect using ImageLabels. The effect is still authored in
--> the Properties panel like any other emitter, so nobody has to learn a config table.
-->
-->     local Spray = require(ReplicatedStorage.Packages.Spray)
-->     local vfx = Spray.New(frame.Sparkles)   -- a ParticleEmitter under a GuiObject
-->     vfx:Emit(40)
-->
--> Everything here is built around a clock. A Spray keeps a single number, its position in
--> its own timeline, and every method either moves that number or stops it. There's no
--> per-frame integration: which particles are alive and where each one is are both
--> computed straight from the clock (Simulation.luau has the details). That's why the
--> clock can run backwards, and why :SetTime() gives you the exact same frame you would
--> have seen by playing up to that point.
-->
-->     :Emit()     queue a burst and start playing
-->     :Pause()    stop the clock, particles freeze where they are
-->     :Resume()   start the clock again from wherever it stopped
-->     :Forward()  move the clock by +/- seconds, paused or not
-->     :SetTime()  jump the clock to a specific second
-->
--> Everything except :Emit() leaves the Spray paused (a new Spray starts paused too), so
--> New -> SetTime(0.5) -> Resume() starts playing half a second in. Calling :Emit() on a
--> paused Spray rewinds to zero and starts over. On a running one it adds another burst on
--> top of whatever is already flying, same as ParticleEmitter:Emit().
-->
--> HOW PROPERTIES MAP. Every ParticleEmitter property is supported, but three of them
--> describe things that only exist in a 3D scene, so they needed a decision:
-->
-->   ZOffset       is added to the parent's ZIndex and used as the ImageLabel's ZIndex, so
-->                 emitters stack against each other the way they were authored. There's
-->                 a limit though. Under ZIndexBehavior.Sibling a GuiObject can never go
-->                 above its parent's siblings, so ZOffset only sorts emitters that share
-->                 a host. If you need a layer in front of some other piece of UI, put it
-->                 under a HOST that is already in front, because no ZIndex on the
-->                 particle will get it out of its own subtree.
-->   one stud      is the parent GuiObject's height in pixels. Everything scales off this,
-->                 so a Spray sizes itself from the UI it lives in and still looks right
-->                 after a resize or on a phone. SprayUnit picks a different edge and
-->                 SprayScale multiplies the whole thing.
-->   LightEmission is emulated, since GUI has no additive blend mode. The header of
-->                 Renderer.luau explains what you get out of that and what you don't.
-->
--> LockedToPart isn't implemented on purpose. The pool is parented to the emitter's
--> GuiObject, so it already acts like LockedToPart = true: move or tween the parent and
--> the particles go with it. The unlocked version would pin particles to the screen while
--> the parent moves away, and for that we'd have to remember where the parent was when
--> each particle SPAWNED. Keeping no history is exactly what makes scrubbing possible, so
--> that's a bad trade for an effect nobody has asked for. If someone ever needs it, give it
--> its own emitter parented higher up.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
-- Copyright (C) 2026 Mastedore.
--
-- The --[=[ ]=] blocks in this file are Moonwave doc comments, which become the API page of
-- the docs site. Keep internal comments on plain -- so Moonwave doesn't try to publish them.

local Renderer = require(script.Renderer);
local Scheduler = require(script.Scheduler);
local Simulation = require(script.Simulation);
local Spec = require(script.Spec);
local Types = require(script.Types);

type Burst = Types.Burst;
type ParticleFrame = Types.ParticleFrame;
type PlaybackState = Types.PlaybackState;
type SpecSnapshot = Types.Spec;

-- How many bursts to remember for scrubbing back. Nobody rewinds past this many :Emit()
-- calls, and without a cap an emitter that fires every frame would keep growing this list
-- for the whole session.
const BURST_HISTORY = 64

--[=[
	@class Spray

	Plays a ParticleEmitter on the screen. You put a regular ParticleEmitter inside a GUI
	object, set it up in the Properties window the same way you would for a 3D effect, and
	Spray draws its particles with ImageLabels.

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Spray = require(ReplicatedStorage.Packages.Spray)

	local button = script.Parent -- a TextButton with a ParticleEmitter called Confetti inside
	local confetti = Spray.New(button.Confetti)

	button.Activated:Connect(function()
		confetti:Emit(40)
	end)
	```

	Spray draws on the client, so require it from a LocalScript, or from a ModuleScript that a
	LocalScript requires.

	## Where the emitter goes

	Roblox only draws a ParticleEmitter that's inside a Part or an Attachment, so one inside a
	GUI does nothing on its own. Spray is what draws it. The emitter needs a GuiObject above it
	in the Explorer, like a Frame, an ImageLabel or a TextButton. It's usually a direct child,
	but a Folder in between works too, which is handy for keeping several effects under one
	button.

	Particles come out of the center of that GuiObject and are drawn inside it, so they move,
	scale and hide along with it. If you tween the frame, the effect follows. When the
	GuiObject, or anything above it, has `ClipsDescendants` on, particles get cut off at its
	edges unless you set the `SprayIgnoreClips` attribute.

	What the effect looks like comes from the emitter's own properties: Texture, Color, Size,
	Transparency, Squash, Lifetime, Speed, Rotation, RotSpeed, Acceleration, Drag,
	SpreadAngle, EmissionDirection, Shape, the flipbook settings, Rate, TimeScale and the
	rest. The few settings a 3D emitter has no property for are attributes, listed further
	down.

	## Playing, pausing and the clock

	Every Spray has a clock that counts seconds from the start of the effect. What you see on
	screen is always calculated from that number and nothing else, so an effect can be
	paused, jumped to any moment, or played backwards, and you still get exactly the frame
	you'd have seen by playing up to that point.

	A Spray is either playing, which means the clock moves forward every frame, or paused. A
	new Spray starts paused at 0 seconds.

	- [Spray:Emit] releases particles. On a paused Spray it first rewinds to 0 and starts
	  playing. On a Spray that's already playing, the new particles join the ones already on
	  screen, the same as `ParticleEmitter:Emit()`.
	- [Spray:Pause] stops the clock and [Spray:Resume] starts it again.
	- [Spray:Forward] and [Spray:SetTime] move the clock. They don't pause or resume anything.

	If the emitter has `Enabled` on and a `Rate` above 0, it also releases particles on its
	own for as long as the Spray is playing, like a 3D emitter does, so calling
	[Spray:Resume] is enough to start it.

	## Attributes

	These are the settings a 3D emitter has no property for. They all go on the
	ParticleEmitter itself, and they're all optional. To add one, select the emitter, scroll to
	the bottom of the Properties window, press the + button next to Attributes, and type the
	name and type exactly as they appear here.

	| Attribute | Type | Default | What it does |
	| --- | --- | --- | --- |
	| `SprayScale` | number | `1` | Multiplies size and speed together, so the whole effect gets bigger or smaller without changing its shape. When an effect looks right but is the wrong size, change this one first. |
	| `SpraySizeScale` | number | `1` | Multiplies size only, on top of `SprayScale`. |
	| `SpraySpeedScale` | number | `1` | Multiplies speed only, on top of `SprayScale`. |
	| `SprayUnit` | string | `RelativeYY` | Which side of the GuiObject counts as one stud. `RelativeYY` is its height, `RelativeXX` its width, `RelativeMin` the shorter side and `RelativeMax` the longer one. `Offset` makes one stud equal one pixel. |
	| `SprayEmissionSize` | Vector2 | `0, 0` | Size of the area particles come out of, as a fraction of the GuiObject. `0, 0` is a single point in the middle and `1, 1` covers the whole GuiObject. The emitter's Shape, ShapeStyle and ShapeInOut are only used when this isn't `0, 0`. |
	| `SprayMaxParticles` | number | `400` | The most particles that can be on screen at once. [Spray:Emit] never releases more than this, and a `Rate` too high to fit gets lowered. |
	| `SprayGlowLayers` | number | `1` | How many copies of each particle get drawn, from 1 to 8. The extra copies are a fading halo that imitates `LightEmission`. Each copy is one more ImageLabel, so it costs performance. |
	| `SprayZIndex` | number | the GuiObject's ZIndex | The ZIndex that `ZOffset` gets added to. |
	| `SprayFlipbookGrid` | number | `4` | Frames per row of the flipbook when `FlipbookLayout` is `Custom`. The other layouts already say how many frames they have. |
	| `SprayFlipbookResolution` | number | `1024` | Size of the flipbook texture in pixels. Spray needs it to cut each frame out of the sheet. |
	| `SprayIgnoreClips` | boolean | `false` | Lets particles leave the GuiObject even when it, or something above it, has `ClipsDescendants` on. |
	| `SprayPrewarm` | number | `0` | How many particles to create ahead of time when the Spray is built. It does the same as calling [Spray:Prewarm] with that number. |

	An attribute with the wrong type, like a string where a number should go, is ignored and
	the default is used instead.

	## From 3D to the screen

	One stud is the height of the GuiObject in pixels, or whichever side `SprayUnit` picks. In
	a frame 200 pixels tall, a Size of 0.1 gives particles 20 pixels across, and a Speed of 2
	moves them 400 pixels per second. Because it's based on the GuiObject and not on the
	screen, the effect keeps its look on a phone or after the window is resized.

	`Acceleration` gets its Y flipped because on the screen +Y points down, so gravity written
	as `0, -10, 0` still pulls the particles down.

	For `EmissionDirection`, Top, Bottom, Left and Right point where you'd expect on the
	screen. Front and Back point into and out of the screen, which a flat GUI can't show, so
	both work like Top. Only the X of `SpreadAngle` is used, and 180 spreads particles all the
	way around.

	`ZOffset` is added to the base ZIndex (see `SprayZIndex`), so emitters in the same
	GuiObject stack the way you'd expect. It can't lift particles above the GuiObject's
	siblings when the ScreenGui uses `ZIndexBehavior.Sibling`, though. If an effect has to
	show in front of some other part of your UI, put it inside a GuiObject that's already in
	front.

	GUIs only have normal alpha blending, so `LightEmission` is imitated. `Brightness` above 1
	pushes colors toward white, which gives you the bright core glowing particles have, and
	`SprayGlowLayers` adds a halo scaled by `LightEmission`. Overlapping particles still don't
	add their light together the way they do in 3D. `LightInfluence` tints the particles
	toward `Lighting.Ambient`.

	Particles always move with their GuiObject, as if `LockedToPart` were on.

	## The Spray type

	The module exports the type of the object [Spray.New] returns as `Spray.Spray`. You only
	need it to annotate variables or function parameters in your own code:

	```lua
	local Spray = require(ReplicatedStorage.Packages.Spray)

	local effects: { Spray.Spray } = {}

	local function PlayAll(list: { Spray.Spray })
		for _, effect in list do
			effect:Emit(20)
		end
	end
	```
]=]
local Spray = {}
Spray.__index = Spray
Spray.__tostring = function(self: any): string
	return `Spray [{self.Emitter:GetFullName()}]`;
end

-- Set as the metatable by :Destroy(), so using a stale reference throws a clear error
-- instead of indexing nil in some unrelated place.
const DESTROYED = table.freeze({
	__index = function(): never
		error("Spray: this object has been destroyed", 2)
	end,
	__newindex = function(): never
		error("Spray: this object has been destroyed", 2)
	end,
	__tostring = function(): string
		return "Spray [destroyed]"
	end,
})

--[=[
	@prop Emitter ParticleEmitter
	@within Spray
	@readonly

	The ParticleEmitter this Spray plays, the same one you passed to [Spray.New]. Spray reads
	it but never changes or destroys it.
]=]
export type Spray = typeof(setmetatable(
	{} :: {
		Emitter: ParticleEmitter,

		_state: PlaybackState,
		_clock: number,
		_bursts: { Burst },
		_burstCounter: number,

		_seed: number,
		_fixedSeed: number,
		_useRandom: boolean,

		_spec: SpecSnapshot?,
		_renderer: Renderer.Renderer?,

		_frame: ParticleFrame,
		_pass: number,
		_expired: { Renderer.Slot },
	},
	Spray
))

-- -- Internals -----------------------------------------------------------------

-- Builds the spec and the renderer the first time they're needed, and again after
-- :Cleanup(). The spec is read here and not in New so a rebuilt Spray sees any property
-- changes made in the meantime.
local function Build(self: Spray)
	if self._spec then
		return
	end
	local snapshot = Spec.Read(self.Emitter)
	self._spec = snapshot
	local draw = Renderer.New(snapshot)
	self._renderer = draw
	if snapshot.Prewarm > 0 then
		Renderer.Prewarm(draw, snapshot.Prewarm)
	end
end

-- Draws one particle. If this is the frame it was born on, its constants get derived first.
local function Visit(
	self: Spray,
	Snapshot: SpecSnapshot,
	Draw: Renderer.Renderer,
	Key: number,
	SpawnTime: number,
	PixelsPerStud: number,
	ParentWidth: number,
	ParentHeight: number
)
	-- A particle that's past its lifetime and doesn't hold a slot was already drawn for the
	-- last time. Bursts stay in the search window until the LONGEST possible lifetime is up,
	-- so without this check every particle that died early would grab a slot, get all its
	-- constants derived again and hand the slot back, on every frame until then.
	if not Draw.Active[Key] and self._clock - SpawnTime >= Simulation.Lifetime(Snapshot, self._seed, Key) then
		return
	end

	local slot = Renderer.Acquire(Draw, Key)
	if not slot then
		return -- the pool is full (SprayMaxParticles)
	end

	local resolved = slot :: Renderer.Slot
	if resolved.Constants.Key ~= Key then
		Simulation.Derive(Snapshot, self._seed, Key, SpawnTime, resolved.Constants)
	end

	local frame = self._frame
	if Simulation.Resolve(
		Snapshot, resolved.Constants, self._seed, self._clock,
		PixelsPerStud, ParentWidth, ParentHeight, frame
	) then
		Renderer.Draw(Draw, resolved, frame)
		resolved.Pass = self._pass
	else
		Renderer.Release(Draw, resolved)
	end
end

-- Draws every particle in one burst. The caller has already checked that the clock is
-- inside the burst's window.
local function VisitBurst(
	self: Spray,
	Snapshot: SpecSnapshot,
	Draw: Renderer.Renderer,
	Queued: Burst,
	PixelsPerStud: number,
	ParentWidth: number,
	ParentHeight: number
)
	local base = Queued.Index * Snapshot.MaxParticles
	for offset = 0, Queued.Count - 1 do
		Visit(self, Snapshot, Draw, (base + offset) * 2 + 1, Queued.Time, PixelsPerStud, ParentWidth, ParentHeight)
	end
end

-- Evaluates the whole emitter at the current clock and draws it.
--
-- Steady stream particles get even keys and burst particles get odd ones, so the two can
-- never end up fighting over the same slot.
local function Render(self: Spray)
	Build(self)

	local snapshot = self._spec :: SpecSnapshot
	local draw = self._renderer :: Renderer.Renderer
	local parent = snapshot.Parent

	-- While the parent is out of the tree there's nothing to measure against, because
	-- AbsoluteSize reads zero and every particle would collapse into a single point.
	if not parent:IsDescendantOf(game) then
		return
	end

	Renderer.Follow(draw)

	local pixelsPerStud = Spec.PixelsPerStud(snapshot)
	local parentSize = parent.AbsoluteSize
	local parentWidth, parentHeight = parentSize.X, parentSize.Y
	local clock = self._clock
	local maximumLifetime = Simulation.MaximumLifetime(snapshot)

	-- Every slot drawn in this pass gets stamped with its number, so the ones left with an
	-- older stamp at the end are the dead ones. Clearing and refilling a set of keys did the
	-- same job, but cost more than drawing some of the particles.
	self._pass += 1
	local pass = self._pass

	-- The steady stream. Particle i is born at i / rate, so the ones that might still be
	-- alive fit in a fixed window that ends at the current clock, and we don't need to
	-- keep a list of them.
	if snapshot.Enabled and snapshot.Rate > 0 then
		-- Rate gets clamped to what the pool can hold, because emitters that are only used
		-- for bursts often have it left at some absurd value.
		local rate = math.min(snapshot.Rate, snapshot.MaxParticles / maximumLifetime)
		local newest = math.floor(clock * rate)
		local oldest = math.max(0, math.ceil((clock - maximumLifetime) * rate))
		for index = oldest, newest do
			Visit(self, snapshot, draw, index * 2, index / rate, pixelsPerStud, parentWidth, parentHeight)
		end
	end

	for _, burst in self._bursts do
		if clock < burst.Time or clock >= burst.Time + maximumLifetime then
			continue
		end
		VisitBurst(self, snapshot, draw, burst, pixelsPerStud, parentWidth, parentHeight)
	end

	-- Any slot that wasn't visited in this pass belongs to a dead particle. We collect them
	-- first and release them after, since releasing modifies the table we're iterating.
	local expired = self._expired
	table.clear(expired)
	for _, slot in draw.Active do
		if slot.Pass ~= pass then
			table.insert(expired, slot)
		end
	end
	for _, slot in expired do
		Renderer.Release(draw, slot)
	end
end

-- Draws a burst that was just queued, and nothing else. Everything already on screen is
-- where the clock put it, and drawing the whole emitter again on every :Emit() made rapid
-- bursts on a busy effect cost a full extra frame each.
local function DrawBurst(self: Spray, Queued: Burst)
	local snapshot = self._spec :: SpecSnapshot
	local parent = snapshot.Parent
	if not parent:IsDescendantOf(game) then
		return
	end

	local draw = self._renderer :: Renderer.Renderer
	Renderer.Follow(draw)

	local parentSize = parent.AbsoluteSize
	VisitBurst(self, snapshot, draw, Queued, Spec.PixelsPerStud(snapshot), parentSize.X, parentSize.Y)
end

-- Rewinds the timeline to the start and drops everything in flight. With UseRandom on, the
-- next run also gets a new seed. This is the only place a Spray uses a real random number.
local function Restart(self: Spray)
	self._clock = 0
	self._burstCounter = 0
	table.clear(self._bursts)

	if self._useRandom then
		self._seed = math.random(0, 2147483647)
	else
		self._seed = self._fixedSeed
	end

	local draw = self._renderer
	if draw then
		Renderer.ReleaseAll(draw)
	end
end

--[=[
	@ignore

	Called by the shared scheduler, and only while Playing.
]=]
function Spray.Advance(self: Spray, DeltaTime: number)
	local snapshot = self._spec
	self._clock += DeltaTime * (if snapshot then snapshot.TimeScale else 1)
	Render(self)
end

-- -- Construction --------------------------------------------------------------

-- The pool is one Frame parented next to the emitter, with an ImageLabel for each live
-- particle. Giving it its own frame means that if the parent uses a UIListLayout, the layout
-- won't try to arrange the particles.
--[=[
	Creates a Spray that plays `Target`.

	This reads the emitter's properties and attributes, and adds an empty Frame inside the
	GuiObject where the particles will be drawn. The Frame is named `Spray_` plus the
	emitter's name. Nothing shows up yet, because the Spray starts paused at 0 seconds.
	Particles appear after [Spray:Emit], or after [Spray:Resume] on an emitter that uses
	`Rate`.

	```lua
	local sparkles = Spray.New(frame.Sparkles)
	sparkles:Emit(30)
	```

	Create each Spray once and keep it around. Calling `Spray.New` every time you want a
	burst builds a new Frame and new ImageLabels on every call, and the old ones stay in your
	UI until you call [Spray:Destroy] on the Sprays that made them.

	@param Target ParticleEmitter -- The emitter to play. It needs a GuiObject somewhere above it.
	@return Spray
	@error "Spray.New expects a ParticleEmitter" -- What you passed isn't a ParticleEmitter.
	@error "Spray: ... has no GuiObject ancestor to draw into" -- Nothing above the emitter is a GuiObject, for example because it's inside a Part.
]=]
function Spray.New(Target: ParticleEmitter): Spray
	assert(typeof(Target) == "Instance" and Target:IsA("ParticleEmitter"), "Spray.New expects a ParticleEmitter")

	local self: Spray = setmetatable({
		Emitter = Target,

		_state = "Paused" :: PlaybackState,
		_clock = 0,
		_bursts = {},
		_burstCounter = 0,

		_seed = math.random(0, 2147483647),
		_fixedSeed = 0,
		_useRandom = true,

		_spec = nil,
		_renderer = nil,

		_frame = {
			Alive = false,
			X = 0, Y = 0,
			Width = 0, Height = 0,
			Rotation = 0,
			Transparency = 0,
			Color = Color3.new(1, 1, 1),
			RectOffsetX = 0, RectOffsetY = 0, RectSize = 0,
		},
		_pass = 0,
		_expired = {},
	}, Spray)

	Build(self)
	return self
end

-- -- Playback ------------------------------------------------------------------

--[=[
	@method Emit
	@within Spray

	Releases `Count` particles at once.

	What happens depends on whether the Spray is playing:

	- If it's paused, it rewinds to 0 seconds, clears whatever was on screen and starts
	  playing, so the effect runs from the beginning. A new Spray is paused, and so is one
	  you stopped with [Spray:Pause]. Moving the clock with [Spray:SetTime] or
	  [Spray:Forward] first doesn't change this, since those don't start playback.
	- If it's already playing, the new particles join the ones already on screen, the same as
	  `ParticleEmitter:Emit()` does in 3D.

	```lua
	button.Activated:Connect(function()
		sparkles:Emit(25)
	end)
	```

	`Count` is rounded down and capped at `SprayMaxParticles`. Passing 0 releases nothing, but
	a paused Spray still rewinds and starts playing, which is a way to restart only the
	`Rate` stream.

	:::caution
	A Spray remembers its last 64 bursts. If you call this more than 64 times within one
	particle lifetime, the oldest bursts disappear early. For a steady flow of particles, use
	the emitter's `Rate` instead.
	:::

	@param Count number -- How many particles to release.
]=]
function Spray.Emit(self: Spray, Count: number)
	Build(self)

	if self._state ~= "Playing" then
		Restart(self)
		self._state = "Playing"
		Scheduler.Add(self)
	end

	local snapshot = self._spec :: SpecSnapshot
	local count = math.clamp(math.floor(Count), 0, snapshot.MaxParticles)
	if count <= 0 then
		return
	end

	local queued: Burst = {
		Time = self._clock,
		Count = count,
		Index = self._burstCounter,
	}
	table.insert(self._bursts, queued)
	self._burstCounter += 1

	if #self._bursts > BURST_HISTORY then
		table.remove(self._bursts, 1)
	end

	DrawBurst(self, queued)
end

-- The particles can stay exactly where they are because their positions were never a
-- running total. They're just whatever the clock evaluates to.
--[=[
	@method Pause
	@within Spray

	Stops the clock. The particles stay on screen, frozen where they are, until the clock
	moves again.

	```lua
	fx:Pause()
	task.wait(1)
	fx:Resume() -- carries on from the same moment
	```

	Pausing doesn't hide anything. If you want the particles gone right away, [Spray:Cleanup]
	removes them. Does nothing if the Spray is already paused.
]=]
function Spray.Pause(self: Spray)
	if self._state == "Paused" then
		return
	end
	self._state = "Paused"
	Scheduler.Remove(self)
end

--[=[
	@method Resume
	@within Spray

	Starts the clock again from wherever it is. That's where [Spray:Pause] stopped it, or
	wherever [Spray:SetTime] or [Spray:Forward] moved it.

	Unlike [Spray:Emit], this doesn't rewind, so you can use it to start an effect partway
	through. On an emitter that uses `Rate`, that makes it start already full of particles
	instead of empty:

	```lua
	local smoke = Spray.New(frame.Smoke)
	smoke:SetTime(2)
	smoke:Resume() -- plays as if it had been running for 2 seconds
	```

	It's also all you need to start a `Rate` emitter, since the stream runs whenever the
	Spray is playing. Does nothing if the Spray is already playing.
]=]
function Spray.Resume(self: Spray)
	if self._state == "Playing" then
		return
	end
	Build(self)
	self._state = "Playing"
	Scheduler.Add(self)
end

--[=[
	@method Forward
	@within Spray

	Moves the clock by `DeltaTime` seconds and redraws right away. Negative values go
	backwards, and the clock never goes below 0.

	It doesn't pause or resume the Spray, so a playing Spray keeps playing from the new
	moment. On a paused one it works like a scrubber:

	```lua
	fx:Emit(30)
	fx:Pause()
	fx:Forward(0.1) -- 0.1 seconds into the effect
	fx:Forward(-0.05) -- back to 0.05
	```

	`TimeScale` changes how fast the clock runs while the Spray is playing, but it doesn't
	affect this method, so `Forward(1)` always moves the clock exactly 1 second.

	@param DeltaTime number -- Seconds to move the clock. Negative values go backwards.
]=]
function Spray.Forward(self: Spray, DeltaTime: number)
	Build(self)
	self._clock = math.max(0, self._clock + DeltaTime)
	Render(self)
end

--[=[
	@method SetTime
	@within Spray

	Jumps the clock to `Time` seconds after the start of the effect and redraws right away.
	You get exactly the frame you'd have seen by playing up to that moment.

	Like [Spray:Forward], it doesn't pause or resume anything, and like `Forward` it ignores
	`TimeScale`. Negative values count as 0.

	```lua
	fx:Emit(60)
	fx:Pause()
	fx:SetTime(0.35) -- the effect as it looks 0.35 seconds in
	```

	@param Time number -- Seconds from the start of the effect.
]=]
function Spray.SetTime(self: Spray, Time: number)
	Build(self)
	self._clock = math.max(0, Time)
	Render(self)
end

-- -- Pool ----------------------------------------------------------------------

--[=[
	@method Prewarm
	@within Spray

	Creates the ImageLabels for `Count` particles now, so later bursts reuse them instead of
	creating new ones in the middle of gameplay.

	Creating ImageLabels is most of what the first burst of an effect costs, and a big burst
	can cause a small hitch. Calling this during a loading screen, or anywhere a hitch won't
	be noticed, moves that cost there.

	```lua
	local explosion = Spray.New(frame.Explosion)
	explosion:Prewarm() -- room for SprayMaxParticles particles
	```

	`Count` is the total the pool should hold, not how many to add, so calling `Prewarm(100)`
	twice still leaves room for 100. It never goes past `SprayMaxParticles`. With
	`SprayGlowLayers` above 1, each particle takes that many ImageLabels.

	[Spray:Cleanup] throws the pool away. The `SprayPrewarm` attribute does the same as this
	method every time the Spray is built, including rebuilds after a cleanup.

	@param Count number? -- How many particles to prepare. Leave it out to use `SprayMaxParticles`.
]=]
function Spray.Prewarm(self: Spray, Count: number?)
	Build(self)
	local snapshot = self._spec :: SpecSnapshot
	Renderer.Prewarm(self._renderer :: Renderer.Renderer, Count or snapshot.MaxParticles)
end

-- -- Determinism ---------------------------------------------------------------

--[=[
	@method UseRandom
	@within Spray

	Chooses whether each run of the effect looks different or exactly the same.

	With `true`, which is the default, the Spray picks a new random seed every time the effect
	restarts, so no two runs look alike. That's what a 3D emitter does. With `false`, it
	always uses the seed set with [Spray:RandomSeed], so every run is identical, down to the
	flipbook frame each particle shows.

	```lua
	fx:UseRandom(false)
	fx:RandomSeed(7)
	fx:Emit(40) -- looks the same every time
	```

	The change applies the next time the effect restarts, which is the next [Spray:Emit] on a
	paused Spray. Particles already on screen keep the seed they have.

	@param Use boolean? -- `true` or `nil` for a new seed on every run, `false` to always use the fixed seed.
]=]
function Spray.UseRandom(self: Spray, Use: boolean?)
	self._useRandom = if Use == nil then true else Use
end

--[=[
	@method RandomSeed
	@within Spray

	Sets the seed used while [Spray:UseRandom] is `false`. The same seed always gives the same
	particles, down to which flipbook frame each one shows. A different seed gives different
	particles, and those repeat exactly too.

	Call it before [Spray:Emit]. If `UseRandom(false)` is already on, the new seed applies
	immediately, even to an effect that's in the middle of playing, so for a clean result set
	the seed first and emit after.

	Decimals are rounded down. Until you call this, the seed is 0.

	@param Seed number -- Any whole number.
]=]
function Spray.RandomSeed(self: Spray, Seed: number)
	self._fixedSeed = math.floor(Seed) % 4294967296
	if not self._useRandom then
		self._seed = self._fixedSeed
	end
end

-- -- Teardown ------------------------------------------------------------------

--[=[
	@method Cleanup
	@within Spray

	Throws away everything the Spray built: the particles on screen, the Frame and ImageLabels
	that draw them, and the copy of the emitter's settings. The Spray itself keeps working,
	but it has to build all of that again the next time you use it.

	There are two reasons to call it:

	- You changed the emitter's properties or attributes while the game is running. Spray
	  only reads them when it builds, so call this and the next call reads them again.
	- You're done with a heavy effect for a while and want its ImageLabels gone.

	```lua
	fx.Emitter.Color = ColorSequence.new(Color3.new(1, 0, 0))
	fx:Cleanup()
	fx:Emit(20) -- red particles now
	```

	After this the Spray is paused at 0 seconds. The next [Spray:Emit], [Spray:Resume],
	[Spray:Forward], [Spray:SetTime] or [Spray:Prewarm] builds everything again, which costs
	about as much as creating the Spray did, so don't call this between bursts of an effect
	you'll keep using. Your [Spray:UseRandom] and [Spray:RandomSeed] settings are kept.
]=]
function Spray.Cleanup(self: Spray)
	Scheduler.Remove(self)

	local draw = self._renderer
	if draw then
		Renderer.Destroy(draw)
	end

	self._renderer = nil
	self._spec = nil
	self._state = "Paused"
	self._clock = 0
	self._burstCounter = 0
	table.clear(self._bursts)
	table.clear(self._expired)
end

--[=[
	@method Destroy
	@within Spray

	Cleans up the Spray for good. It does what [Spray:Cleanup] does and then makes the object
	unusable, so anything you do with it afterwards, including calling `:Destroy()` again,
	throws "Spray: this object has been destroyed". That way a leftover reference fails
	loudly where you use it instead of misbehaving somewhere else.

	The ParticleEmitter isn't touched. Destroy it yourself if you don't need it anymore.

	Call this when the UI the effect lives in goes away. If you destroy the UI but not the
	Spray, a Spray that was playing stays in Spray's update loop and in memory.
]=]
function Spray.Destroy(self: Spray)
	Spray.Cleanup(self)
	table.clear(self :: any)
	setmetatable(self :: any, DESTROYED)
end

return Spray

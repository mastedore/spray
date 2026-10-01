--!strict
--!native

--[[

	Connected Discord-GitHub

]]

-->> Simulation.luau
--> The physics. The whole file rests on two ideas.
-->
--> First, a particle's state depends only on its age. Constant acceleration with linear
--> drag has a closed-form solution, so instead of pushing the velocity forward a bit every
--> frame we just solve for where the particle IS at age t. Nothing piles up, so nothing
--> drifts with the framerate, and more importantly for us, t can go backwards. That's why
--> :Forward(-0.2) and :SetTime() are exact and not an approximation.
-->
--> Second, which particles exist also depends only on the clock. A particle is born at a
--> time set by the emission schedule (index / rate for the steady stream, the burst time
--> for an :Emit), dies one lifetime later, and every random roll it makes is a hash of its
--> own index. So to get the state at time t we never have to step through everything that
--> came before, we can compute it directly.
-->
--> Units: spawn offsets are a FRACTION of the parent GuiObject and velocities are in studs
--> per second. Neither depends on resolution, and the conversion to pixels only happens
--> once, at the end, in Resolve.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local Sampling = require(script.Parent.Sampling)
local Types = require(script.Parent.Types)

type Spec = Types.Spec
type ParticleFrame = Types.ParticleFrame

--- Every rolled property has its own hash channel, so tweaking one emitter property doesn't
--- reshuffle all the other rolls a particle made.
const CHANNEL_LIFETIME = 1
const CHANNEL_SPEED = 2
const CHANNEL_SPREAD = 3
const CHANNEL_ROTATION = 4
const CHANNEL_ROTSPEED = 5
const CHANNEL_SIZE_ENVELOPE = 6
const CHANNEL_TRANSPARENCY_ENVELOPE = 7
const CHANNEL_SQUASH_ENVELOPE = 8
const CHANNEL_SHAPE_U = 9
const CHANNEL_SHAPE_V = 10
const CHANNEL_SHAPE_SIGN = 11
const CHANNEL_FLIPBOOK_START = 12
const CHANNEL_FLIPBOOK_RATE = 13
const CHANNEL_FLIPBOOK_RANDOM = 14

--- Drag below this counts as zero. The closed-form solution divides by drag, and both
--- branches give the same result as drag approaches zero, so this cutoff only picks which
--- formula runs.
const DRAG_EPSILON = 1e-4

--- exp() of a big positive number is infinity, and negative drag gives it exactly that.
--- With the clamp, a badly set Drag just makes an ugly particle, instead of a NaN that
--- breaks the position and makes the ImageLabel disappear.
const MAX_DECAY_EXPONENT = 60

--- Enum items read once here instead of through three lookups on the global Enum for every
--- particle on every frame.
const FACING_CAMERA = Enum.ParticleOrientation.FacingCamera
const FACING_CAMERA_WORLD_UP = Enum.ParticleOrientation.FacingCameraWorldUp
const VELOCITY_PERPENDICULAR = Enum.ParticleOrientation.VelocityPerpendicular
const FLIPBOOK_ONE_SHOT = Enum.ParticleFlipbookMode.OneShot
const FLIPBOOK_LOOP = Enum.ParticleFlipbookMode.Loop
const FLIPBOOK_PING_PONG = Enum.ParticleFlipbookMode.PingPong

local Simulation = {}

export type Constants = {
	Key: number,
	SpawnTime: number,
	Lifetime: number,
	OffsetX: number,      -- fraction of the parent GuiObject
	OffsetY: number,
	VelocityX: number,    -- studs/second
	VelocityY: number,
	Rotation: number,     -- degrees
	RotationSpeed: number,
	SizeRoll: number,     -- envelope rolls, fixed for the particle's whole life
	TransparencyRoll: number,
	SquashRoll: number,
	FlipbookStart: number,
	FlipbookRate: number,
}

-- -- Emission ------------------------------------------------------------------

--- Where in the emission area the particle appears, and which way it faces before spread
--- is applied. Offsets are a fraction of the parent so they still work after a resize.
local function Spawn(Snapshot: Spec, Stream: number): (number, number, number, number)
	local halfWidth = Snapshot.EmissionSize.X * 0.5
	local halfHeight = Snapshot.EmissionSize.Y * 0.5

	local baseX = Snapshot.EmissionDirection.X
	local baseY = Snapshot.EmissionDirection.Y

	-- A zero-size area is a point emitter. That's how a 3D emitter under an Attachment
	-- behaves, and it's the most common case. There's no position to pick and no normal to
	-- work out, so we just use the authored EmissionDirection.
	if halfWidth <= 0 and halfHeight <= 0 then
		return 0, 0, baseX, baseY
	end

	local u = Sampling.Unit(Stream, CHANNEL_SHAPE_U)
	local v = Sampling.Unit(Stream, CHANNEL_SHAPE_V)

	local offsetX, offsetY
	local normalX, normalY

	if Snapshot.Shape == Enum.ParticleEmitterShape.Box then
		if Snapshot.ShapeStyle == Enum.ParticleEmitterShapeStyle.Surface then
			-- Walk along the perimeter. Picking an edge first and then a point on it would
			-- put too many particles in the corners.
			local perimeter = 2 * (halfWidth + halfHeight)
			local walk = u * perimeter
			if walk < 2 * halfWidth then
				offsetX, offsetY = walk - halfWidth, if v < 0.5 then -halfHeight else halfHeight
			else
				offsetX, offsetY = if v < 0.5 then -halfWidth else halfWidth, (walk - 2 * halfWidth) - halfHeight
			end
		else
			offsetX, offsetY = (u * 2 - 1) * halfWidth, (v * 2 - 1) * halfHeight
		end
		-- A box emits from a face and not outward from its centre, so we use the face
		-- normal as the shape normal.
		normalX, normalY = baseX, baseY
	else
		-- Sphere, Cylinder and Disc all end up as the same ellipse in 2D.
		local angle = u * math.pi * 2
		local radius = if Snapshot.ShapeStyle == Enum.ParticleEmitterShapeStyle.Surface
			then 1
			else math.sqrt(v) -- sqrt keeps the fill even so particles don't bunch up in the centre

		offsetX = math.cos(angle) * radius * halfWidth
		offsetY = math.sin(angle) * radius * halfHeight

		-- An ellipse's outward normal only matches the radius when the ellipse is a circle,
		-- so we take it from the gradient instead.
		local gradientX = if halfWidth > 0 then offsetX / (halfWidth * halfWidth) else 0
		local gradientY = if halfHeight > 0 then offsetY / (halfHeight * halfHeight) else 0
		local length = math.sqrt(gradientX * gradientX + gradientY * gradientY)
		if length > 0 then
			normalX, normalY = gradientX / length, gradientY / length
		else
			normalX, normalY = baseX, baseY
		end
	end

	if Snapshot.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward then
		normalX, normalY = -normalX, -normalY
	elseif Snapshot.ShapeInOut == Enum.ParticleEmitterShapeInOut.InAndOut then
		if Sampling.Unit(Stream, CHANNEL_SHAPE_SIGN) < 0.5 then
			normalX, normalY = -normalX, -normalY
		end
	end

	return offsetX, offsetY, normalX, normalY
end

-- -- Derivation ----------------------------------------------------------------

local function LifetimeOf(Snapshot: Spec, Stream: number): number
	return math.max(Sampling.Range(Stream, CHANNEL_LIFETIME, Snapshot.Lifetime), 1e-3)
end

--- Computes everything about a particle that never changes, once. The caller holds onto
--- the result while the particle is alive. Every field depends only on (Seed, Key), so
--- recomputing it later would give the same values.
function Simulation.Derive(Snapshot: Spec, Seed: number, Key: number, SpawnTime: number, Into: Constants)
	local stream = Sampling.Stream(Seed, Key)
	local offsetX, offsetY, directionX, directionY = Spawn(Snapshot, stream)

	-- SpreadAngle rotates the particle away from its base direction. 180 degrees covers
	-- the full circle, which is what most burst effects use.
	local spread = Snapshot.SpreadAngle
	if spread ~= 0 then
		local angle = math.rad((Sampling.Unit(stream, CHANNEL_SPREAD) * 2 - 1) * spread)
		local cosine, sine = math.cos(angle), math.sin(angle)
		directionX, directionY = directionX * cosine - directionY * sine, directionX * sine + directionY * cosine
	end

	local speed = Sampling.Range(stream, CHANNEL_SPEED, Snapshot.Speed)

	Into.Key = Key
	Into.SpawnTime = SpawnTime
	Into.Lifetime = LifetimeOf(Snapshot, stream)
	Into.OffsetX = offsetX
	Into.OffsetY = offsetY
	Into.VelocityX = directionX * speed
	Into.VelocityY = directionY * speed
	Into.Rotation = Sampling.Range(stream, CHANNEL_ROTATION, Snapshot.Rotation)
	Into.RotationSpeed = Sampling.Range(stream, CHANNEL_ROTSPEED, Snapshot.RotSpeed)
	Into.SizeRoll = Sampling.Signed(stream, CHANNEL_SIZE_ENVELOPE)
	Into.TransparencyRoll = Sampling.Signed(stream, CHANNEL_TRANSPARENCY_ENVELOPE)
	Into.SquashRoll = Sampling.Signed(stream, CHANNEL_SQUASH_ENVELOPE)
	Into.FlipbookRate = Sampling.Range(stream, CHANNEL_FLIPBOOK_RATE, Snapshot.FlipbookFramerate)

	local frameCount = Snapshot.FlipbookFrames * Snapshot.FlipbookFrames
	Into.FlipbookStart = if Snapshot.FlipbookStartRandom and frameCount > 1
		then Sampling.Integer(stream, CHANNEL_FLIPBOOK_START, 1, frameCount)
		else 1
end

--- The lifetime particle `Key` rolls. Derive stores it with the rest of the constants, and
--- the caller uses it on its own to tell that a particle is dead without deriving anything
--- else about it.
function Simulation.Lifetime(Snapshot: Spec, Seed: number, Key: number): number
	return LifetimeOf(Snapshot, Sampling.Stream(Seed, Key))
end

--- The longest lifetime a particle COULD roll, used to limit the search for live
--- particles. Anything older than this is dead no matter what its own roll was.
function Simulation.MaximumLifetime(Snapshot: Spec): number
	return math.max(Snapshot.Lifetime.Max, 1e-3)
end

-- -- Motion --------------------------------------------------------------------

--- Position and velocity at `Age`. They're computed together because both branches share
--- the same terms.
---
--- With drag k and constant acceleration a, dv/dt = a - k*v integrates to
---     v(t) = a/k + (v0 - a/k) * e^(-kt)
---     p(t) = (a/k)*t + (v0 - a/k) * (1 - e^(-kt)) / k
--- which turns into the usual v0*t + a*t^2/2 as k goes to zero.
local function Solve(
	VelocityX: number, VelocityY: number,
	AccelerationX: number, AccelerationY: number,
	Drag: number, Age: number
): (number, number, number, number)
	if math.abs(Drag) < DRAG_EPSILON then
		local half = 0.5 * Age * Age
		return
			VelocityX * Age + AccelerationX * half,
			VelocityY * Age + AccelerationY * half,
			VelocityX + AccelerationX * Age,
			VelocityY + AccelerationY * Age
	end

	local terminalX = AccelerationX / Drag
	local terminalY = AccelerationY / Drag
	local decay = math.exp(math.clamp(-Drag * Age, -MAX_DECAY_EXPONENT, MAX_DECAY_EXPONENT))
	local settled = (1 - decay) / Drag

	local restX = VelocityX - terminalX
	local restY = VelocityY - terminalY

	return
		terminalX * Age + restX * settled,
		terminalY * Age + restY * settled,
		terminalX + restX * decay,
		terminalY + restY * decay
end

--- Which flipbook cell to show. Random mode hashes the frame WINDOW instead of calling
--- math.random, so when you scrub back over a particle it shows the same cells it showed
--- the first time. The old library rerolled here, so it flickered differently on every
--- replay.
local function FlipbookFrame(
	Snapshot: Spec, Constants: Constants, Seed: number, Age: number, Progress: number, FrameCount: number
): number
	local mode = Snapshot.FlipbookMode
	local start = Constants.FlipbookStart

	if mode == FLIPBOOK_ONE_SHOT then
		-- A single pass from the starting cell to the last one, spread over the whole lifetime.
		local span = FrameCount - start + 1
		return math.clamp(start + math.floor(Progress * span), 1, FrameCount)
	end

	local elapsed = math.floor(Age * Constants.FlipbookRate)

	if mode == FLIPBOOK_LOOP then
		return 1 + (start - 1 + elapsed) % FrameCount
	elseif mode == FLIPBOOK_PING_PONG then
		local cycle = (start - 1 + elapsed) % (FrameCount * 2 - 2)
		return 1 + if cycle < FrameCount then cycle else FrameCount * 2 - 2 - cycle
	end

	-- Random
	return Sampling.Integer(Sampling.Stream(Seed, Constants.Key), CHANNEL_FLIPBOOK_RANDOM + elapsed * 32, 1, FrameCount)
end

--- Everything the renderer needs to know about one particle at one moment. It gets written
--- into a scratch struct owned by the caller, so updating a full pool allocates nothing.
---
--- Returns false if the particle isn't alive at `Clock`. In that case the only thing
--- written to `Frame` is its Alive flag.
function Simulation.Resolve(
	Snapshot: Spec,
	Constants: Constants,
	Seed: number,
	Clock: number,
	PixelsPerStud: number,
	ParentWidth: number,
	ParentHeight: number,
	Frame: ParticleFrame
): boolean
	local age = Clock - Constants.SpawnTime
	if age < 0 or age >= Constants.Lifetime then
		Frame.Alive = false
		return false
	end

	local progress = age / Constants.Lifetime

	local offsetX, offsetY, velocityX, velocityY = Solve(
		Constants.VelocityX, Constants.VelocityY,
		Snapshot.Acceleration.X, Snapshot.Acceleration.Y,
		Snapshot.Drag, age
	)

	local travel = PixelsPerStud * Snapshot.SpeedScale
	Frame.X = Constants.OffsetX * ParentWidth + offsetX * travel
	Frame.Y = Constants.OffsetY * ParentHeight + offsetY * travel

	-- Size. Squash turns one number into a width and a height. Roblox treats squash as a
	-- stretch along the particle's own long axis, so the two factors are reciprocal and
	-- the particle keeps the same area.
	local size = Sampling.Number(Snapshot.Size, progress, Constants.SizeRoll)
	local pixels = math.max(size, 0) * PixelsPerStud * Snapshot.SizeScale

	local squash = Sampling.Number(Snapshot.Squash, progress, Constants.SquashRoll)
	local long = 1 + math.abs(squash)
	local short = 1 / long
	if squash >= 0 then
		Frame.Width, Frame.Height = pixels * short, pixels * long
	else
		Frame.Width, Frame.Height = pixels * long, pixels * short
	end

	-- Rotation. In GUI, positive rotation is clockwise. The emitter's authored Rotation is
	-- the starting value and the orientation mode adds on top of it.
	local rotation = Constants.Rotation + Constants.RotationSpeed * age
	local orientation = Snapshot.Orientation
	if orientation ~= FACING_CAMERA and orientation ~= FACING_CAMERA_WORLD_UP then
		-- The velocity-facing modes get their base angle here. ALIGNED is the angle that
		-- lines the particle's local +Y up with the direction of travel. At rotation zero,
		-- +Y points down the screen, and it's also the long axis of anything squashed.
		local aligned = math.deg(math.atan2(-velocityX, velocityY))

		-- VelocityParallel then sits 90 degrees off ALIGNED, because Roblox puts the
		-- particle's local X along the velocity, not its Y. This one is easy to get
		-- backwards. A streak texture is drawn vertically, so an emitter that wants its
		-- streaks pointing where the particle is MOVING gets authored as VelocityParallel
		-- with Rotation 90, and that 90 is what turns the long axis onto the velocity. If
		-- ALIGNED were used as the base instead, every emitter like that would come out a
		-- quarter turn off, with its streaks going sideways across the direction of travel
		-- instead of along it.
		rotation += aligned - 90
		if orientation == VELOCITY_PERPENDICULAR then
			rotation += 90
		end
	end
	Frame.Rotation = rotation

	Frame.Transparency = math.clamp(
		Sampling.Number(Snapshot.Transparency, progress, Constants.TransparencyRoll), 0, 1
	)
	Frame.Color = Sampling.Color(Snapshot.Color, progress)

	local rows = Snapshot.FlipbookFrames
	if rows > 0 then
		local frameCount = rows * rows
		local cell = FlipbookFrame(Snapshot, Constants, Seed, age, progress, frameCount)
		local edge = Snapshot.FlipbookResolution / rows
		Frame.RectSize = edge
		Frame.RectOffsetX = ((cell - 1) % rows) * edge
		Frame.RectOffsetY = math.floor((cell - 1) / rows) * edge
	else
		Frame.RectSize = 0
		Frame.RectOffsetX = 0
		Frame.RectOffsetY = 0
	end

	Frame.Alive = true
	return true
end

return Simulation

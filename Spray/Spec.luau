--!strict
-->> Spec.luau
--> A Spec is a flat, frozen table that describes a ParticleEmitter, and it's what the rest
--> of the package reads instead of the emitter itself.
-->
--> Anything that needs translating to make sense in 2D gets translated HERE and nowhere
--> else. The NormalId turns into a screen-space vector, the Vector3 acceleration gets its Y
--> flipped because GUI space grows downward, the flipbook layout becomes a frame count, and
--> every sequence becomes a plain curve. After that, the simulation and the renderer only
--> deal with numbers and tables and never need to know what a NormalId is.
-->
--> Anything the 3D emitter can't express is read from a Spray-prefixed attribute on the
--> emitter itself, so a Spray is still authored entirely in the Properties panel. The
--> ATTRIBUTES block below lists all of them.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

--------------------------------------------------------------------------------
-- ATTRIBUTES (all optional, all set on the ParticleEmitter)
--------------------------------------------------------------------------------
-- SprayScale              number   1       Multiplies both size AND speed. Try this one
--                                          first, since it rescales the whole effect
--                                          without changing its shape.
-- SpraySizeScale          number   1       Size only, on top of SprayScale.
-- SpraySpeedScale         number   1       Speed only, on top of SprayScale.
-- SprayUnit               string   RelativeYY  Which edge of the parent GuiObject counts
--                                          as one stud. RelativeXX / RelativeMin /
--                                          RelativeMax / Offset (1 stud = 1 pixel).
-- SprayZIndex             number   parent   Base ZIndex that the emitter's ZOffset is added to.
-- SprayMaxParticles       number   400     Hard limit on live particles.
-- SprayGlowLayers         number   1       Stacked copies per particle. This is how
--                                          LightEmission gets emulated (see Renderer).
-- SprayEmissionSize       Vector2  0,0     Emission area as a fraction of the parent size.
--                                          Zero means a point emitter, which is how a 3D
--                                          emitter under an Attachment behaves.
-- SprayFlipbookGrid       number   4       Frames per row when FlipbookLayout is Custom.
-- SprayFlipbookResolution number   1024    Texture size in pixels, used for ImageRectSize.
-- SprayIgnoreClips        boolean  false   Moves the pool out of any clipping ancestor.
-- SprayPrewarm            number   0       ImageLabels to build as soon as the Spray is
--                                          built, so the first burst doesn't create them.
--                                          Same as calling :Prewarm() with that count.
--------------------------------------------------------------------------------

local Sampling = require(script.Parent.Sampling);
local Types = require(script.Parent.Types);

type Spec = Types.Spec;
type UnitMode = Types.UnitMode;

--- In GUI space +Y points DOWN the screen, the opposite of a Roblox part, so every
--- direction that comes from a NormalId gets its Y flipped.
const DIRECTIONS: {[Enum.NormalId]: Vector2} = {
	[Enum.NormalId.Top] = Vector2.new(0, -1),
	[Enum.NormalId.Bottom] = Vector2.new(0, 1),
	[Enum.NormalId.Right] = Vector2.new(1, 0),
	[Enum.NormalId.Left] = Vector2.new(-1, 0),
	-- Front and Back point toward and away from the camera, which on a flat screen isn't
	-- a direction at all. They fall back to Top, and since they're usually paired with a
	-- 180 degree spread you still get the full circle you wanted.
	[Enum.NormalId.Front] = Vector2.new(0, -1),
	[Enum.NormalId.Back] = Vector2.new(0, -1),
};

const FLIPBOOK_ROWS: {[Enum.ParticleFlipbookLayout]: number} = {
	[Enum.ParticleFlipbookLayout.None] = 0,
	[Enum.ParticleFlipbookLayout.Grid2x2] = 2,
	[Enum.ParticleFlipbookLayout.Grid4x4] = 4,
	[Enum.ParticleFlipbookLayout.Grid8x8] = 8,
};

const UNIT_MODES: {[string]: boolean} = {
	RelativeYY = true,
	RelativeXX = true,
	RelativeMin = true,
	RelativeMax = true,
	Offset = true,
};

local Spec = {}

--- Reads an attribute, but only if it has the type we expect. If the type is wrong we use
--- the default instead of passing a nil into the maths, where it would blow up as a
--- confusing error a few modules away.
local function Read<T>(Emitter: ParticleEmitter, Name: string, Default: T): T
	local value = Emitter:GetAttribute(Name)
	if typeof(value) == typeof(Default) then
		return value :: any
	end
	return Default
end

--- The GuiObject a Spray draws inside. Usually it's the emitter's parent, but we walk up
--- the tree in case the emitter was put inside a Folder to keep things tidy.
function Spec.ResolveParent(Emitter: ParticleEmitter): GuiObject?
	local parent = Emitter.Parent
	if parent and parent:IsA("GuiObject") then
		return parent
	end
	return Emitter:FindFirstAncestorWhichIsA("GuiObject")
end

--- Takes a snapshot of the emitter. It runs when the Spray is created and again after
--- :Cleanup(), which is how a rebuilt Spray picks up property changes made in between.
function Spec.Read(Emitter: ParticleEmitter): Spec
	local parent = Spec.ResolveParent(Emitter)
	assert(parent, `Spray: {Emitter:GetFullName()} has no GuiObject ancestor to draw into`)

	local uniform = Read(Emitter, "SprayScale", 1)

	local unitMode = Read(Emitter, "SprayUnit", "RelativeYY")
	if not UNIT_MODES[unitMode] then
		unitMode = "RelativeYY"
	end

	-- Custom layouts store their grid inside the asset, and no runtime API exposes that,
	-- so the author has to tell us.
	local flipbookRows = FLIPBOOK_ROWS[Emitter.FlipbookLayout]
	if flipbookRows == nil then
		flipbookRows = math.max(1, math.floor(Read(Emitter, "SprayFlipbookGrid", 4)))
	end

	local acceleration = Emitter.Acceleration

	return table.freeze({
		Emitter = Emitter,
		Parent = parent,

		Texture = Emitter.Texture,
		Color = Sampling.ColorCurve(Emitter.Color),
		Transparency = Sampling.NumberCurve(Emitter.Transparency),
		Size = Sampling.NumberCurve(Emitter.Size),
		Squash = Sampling.NumberCurve(Emitter.Squash),
		LightEmission = Emitter.LightEmission,
		LightInfluence = Emitter.LightInfluence,
		Brightness = Emitter.Brightness,
		ZOffset = Emitter.ZOffset,
		Orientation = Emitter.Orientation,
		ResampleMode = Enum.ResamplerMode.Default,

		Lifetime = Emitter.Lifetime,
		Speed = Emitter.Speed,
		SpreadAngle = math.abs(Emitter.SpreadAngle.X),
		Rotation = Emitter.Rotation,
		RotSpeed = Emitter.RotSpeed,
		Acceleration = Vector2.new(acceleration.X, -acceleration.Y),
		Drag = Emitter.Drag,
		VelocityInheritance = Emitter.VelocityInheritance,
		EmissionDirection = DIRECTIONS[Emitter.EmissionDirection] or Vector2.new(0, -1),
		TimeScale = Emitter.TimeScale,

		Shape = Emitter.Shape,
		ShapeStyle = Emitter.ShapeStyle,
		ShapeInOut = Emitter.ShapeInOut,
		ShapePartial = Emitter.ShapePartial,
		EmissionSize = Read(Emitter, "SprayEmissionSize", Vector2.zero),
		Rate = math.max(0, Emitter.Rate),
		Enabled = Emitter.Enabled,

		FlipbookFrames = flipbookRows,
		FlipbookMode = Emitter.FlipbookMode,
		FlipbookFramerate = Emitter.FlipbookFramerate,
		FlipbookStartRandom = Emitter.FlipbookStartRandom,
		FlipbookResolution = Read(Emitter, "SprayFlipbookResolution", 1024),

		SizeScale = uniform * Read(Emitter, "SpraySizeScale", 1),
		SpeedScale = uniform * Read(Emitter, "SpraySpeedScale", 1),
		UnitMode = unitMode :: UnitMode,
		ZIndexBase = Read(Emitter, "SprayZIndex", parent.ZIndex),
		MaxParticles = math.max(1, math.floor(Read(Emitter, "SprayMaxParticles", 400))),
		GlowLayers = math.clamp(math.floor(Read(Emitter, "SprayGlowLayers", 1)), 1, 8),
		LockedToParent = true,
		IgnoreClips = Read(Emitter, "SprayIgnoreClips", false),
		Prewarm = math.max(0, math.floor(Read(Emitter, "SprayPrewarm", 0))),
	}) :: any
end



--- How many pixels one stud is worth right now. It's recalculated every step instead of
--- cached in the spec, because the parent resizes with the viewport, and a cached value
--- gives you particles stuck at the wrong size until something forces a rebuild lol
function Spec.PixelsPerStud(Snapshot: Spec): number
	local size = Snapshot.Parent.AbsoluteSize
	local mode = Snapshot.UnitMode
	if mode == "RelativeXX" then
		return size.X
	elseif mode == "RelativeMin" then
		return math.min(size.X, size.Y)
	elseif mode == "RelativeMax" then
		return math.max(size.X, size.Y)
	elseif mode == "Offset" then
		return 1
	end
	return size.Y
end

return Spec

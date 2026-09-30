--!strict
-->> Spray/Types.luau
--> Every type the package passes between its own modules, plus the ones it hands back
--> to callers. They live in one file so the simulation, the renderer and the public class
--> can share the same shapes without requiring each other.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.


--- What the clock is doing. Every public method either moves the clock or stops it, and it
--- only advances by itself while "Playing". The method list at the top of init.luau has
--- the details.
export type PlaybackState = "Playing" | "Paused";

--- How one stud of the source ParticleEmitter is converted to pixels. The reference length
--- comes from the GuiObject the emitter sits under, so a Spray scales with its UI and not
--- with the screen.
export type UnitMode = "RelativeYY" | "RelativeXX" | "RelativeMin" | "RelativeMax" | "Offset";

--- A burst queued by :Emit(). Bursts are stored as data instead of as spawned particles,
--- which keeps the whole simulation a pure function of the clock and lets us move freely
--- through time.
export type Burst = {
	Time: number,   -- clock time when the burst was queued
	Count: number,  -- how many particles it releases
	Index: number,  -- increasing id that seeds the burst's own random stream
};

--- A NumberSequence read into plain tables. Reading .Keypoints off the engine type builds a
--- new table of new keypoint objects on every access, which is fine once but not four
--- times per particle per frame, so Spec.Read converts every sequence up front.
export type NumberCurve = { { Time: number, Value: number, Envelope: number } };

--- Same thing for a ColorSequence, which has no envelope.
export type ColorCurve = { { Time: number, Value: Color3 } };

--- An immutable snapshot of a ParticleEmitter along with its Spray-prefixed attribute
--- overrides. Spec.Read builds it once, :Cleanup() throws it away, and the next use reads
--- the emitter again, which is how live property edits show up.
export type Spec = {
	-- Source
	Emitter: ParticleEmitter,
	Parent: GuiObject,

	-- Appearance
	Texture: string,
	Color: ColorCurve,
	Transparency: NumberCurve,
	Size: NumberCurve,
	Squash: NumberCurve,
	LightEmission: number,
	LightInfluence: number,
	Brightness: number,
	ZOffset: number,
	Orientation: Enum.ParticleOrientation,
	ResampleMode: Enum.ResamplerMode,

	-- Motion
	Lifetime: NumberRange,
	Speed: NumberRange,
	SpreadAngle: number, -- degrees, half angle around the emission axis
	Rotation: NumberRange,
	RotSpeed: NumberRange,
	Acceleration: Vector2, -- studs/s^2, already flipped into GUI space (+Y is down)
	Drag: number,
	VelocityInheritance: number,
	EmissionDirection: Vector2, -- unit vector in GUI space
	TimeScale: number,

	-- Emission volume
	Shape: Enum.ParticleEmitterShape,
	ShapeStyle: Enum.ParticleEmitterShapeStyle,
	ShapeInOut: Enum.ParticleEmitterShapeInOut,
	ShapePartial: number,
	EmissionSize: Vector2, -- fraction of the parent GuiObject, zero means a point
	Rate: number,
	Enabled: boolean,

	-- Flipbook
	FlipbookFrames: number, -- frames per row, 0 when the texture isn't a flipbook
	FlipbookMode: Enum.ParticleFlipbookMode,
	FlipbookFramerate: NumberRange,
	FlipbookStartRandom: boolean,
	FlipbookResolution: number,

	-- Spray-only settings
	SizeScale: number,
	SpeedScale: number,
	UnitMode: UnitMode,
	ZIndexBase: number,
	MaxParticles: number,
	GlowLayers: number,
	LockedToParent: boolean,
	IgnoreClips: boolean,
	Prewarm: number, -- slots to build as soon as the Spray is
};

--- A scratch struct that the solver fills in and the renderer reads back in the same
--- iteration. Each Spray has just one and reuses it for every particle, so updating a full
--- pool allocates nothing.
export type ParticleFrame = {
	Alive: boolean,
	X: number,
	Y: number,
	Width: number,
	Height: number,
	Rotation: number,
	Transparency: number,
	Color: Color3,
	RectOffsetX: number,
	RectOffsetY: number,
	RectSize: number,
};

return nil;

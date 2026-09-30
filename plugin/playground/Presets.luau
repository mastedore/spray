--!strict
-->> Presets.luau
--> Starting points for new origins, each picked to show off a different part of Spray:
--> bursts with glow, velocity-aligned streaks with squash, streams off an emission area,
--> an inward ring, and the raw engine defaults for comparison.
-->
--> Every texture here ships inside the Roblox client under rbxasset://, so the playground
--> works without uploading anything. Only the ones that read on a GUI are listed: several
--> of the built-in particle textures (fire_main, fire_sparks, forcefield_glow) are authored
--> for additive blending and come out nearly black when drawn by an ImageLabel.

local Presets = {}

export type Texture = {
	Name: string,
	Id: string,
}

Presets.Textures = {
	{ Name = "Sparkles", Id = "rbxasset://textures/particles/sparkles_main.dds" },
	{ Name = "Soft glow", Id = "rbxasset://textures/particles/explosion01_implosion_main.dds" },
	{ Name = "Fireball", Id = "rbxasset://textures/particles/explosion01_core_main.dds" },
	{ Name = "Smoke", Id = "rbxasset://textures/particles/smoke_main.dds" },
	{ Name = "Ring", Id = "rbxasset://textures/particles/explosion01_shockwave_main.dds" },
	{ Name = "Vortex", Id = "rbxasset://textures/particles/forcefield_vortex_main.dds" },
	{ Name = "Square", Id = "rbxasset://textures/particles/SquareParticle.png" },
} :: { Texture }

local TEXTURE: { [string]: string } = {}
for _, texture in Presets.Textures do
	TEXTURE[texture.Name] = texture.Id
end

-- -- Sequence helpers ----------------------------------------------------------

--- `{ time, value, envelope? }` rows into a NumberSequence.
local function Numbers(Points: { { number } }): NumberSequence
	local keypoints = {}
	for _, point in Points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2], point[3] or 0))
	end
	return NumberSequence.new(keypoints)
end

--- `{ time, color }` rows into a ColorSequence.
local function Colors(Points: { { any } }): ColorSequence
	local keypoints = {}
	for _, point in Points do
		table.insert(keypoints, ColorSequenceKeypoint.new(point[1], point[2]))
	end
	return ColorSequence.new(keypoints)
end

local rgb = Color3.fromRGB

-- -- Presets -------------------------------------------------------------------

local BUILDERS: { [string]: (ParticleEmitter) -> () } = {
	["Sparkle Burst"] = function(Emitter)
		Emitter.Texture = TEXTURE.Sparkles
		Emitter.Color = Colors({ { 0, rgb(125, 214, 255) }, { 0.5, rgb(177, 140, 255) }, { 1, rgb(255, 122, 217) } })
		Emitter.LightEmission = 1
		Emitter.Brightness = 2
		Emitter.Size = Numbers({ { 0, 0 }, { 0.12, 0.22, 0.06 }, { 1, 0 } })
		Emitter.Transparency = Numbers({ { 0, 0 }, { 0.75, 0.15 }, { 1, 1 } })
		Emitter.Lifetime = NumberRange.new(0.6, 1.1)
		Emitter.Speed = NumberRange.new(1.2, 2.8)
		Emitter.SpreadAngle = Vector2.new(180, 180)
		Emitter.Drag = 3.5
		Emitter.Acceleration = Vector3.new(0, -1.5, 0)
		Emitter.Rotation = NumberRange.new(0, 360)
		Emitter.RotSpeed = NumberRange.new(-180, 180)
		Emitter.Rate = 20
		Emitter.Enabled = false
		Emitter:SetAttribute("BurstCount", 40)
		Emitter:SetAttribute("SprayGlowLayers", 2)
	end,

	Sparks = function(Emitter)
		Emitter.Texture = TEXTURE["Soft glow"]
		Emitter.Color = Colors({ { 0, rgb(255, 246, 204) }, { 0.4, rgb(255, 188, 76) }, { 1, rgb(255, 90, 40) } })
		Emitter.LightEmission = 1
		Emitter.Brightness = 4
		Emitter.Size = Numbers({ { 0, 0.14 }, { 1, 0 } })
		Emitter.Squash = Numbers({ { 0, 2.5 }, { 1, 1 } })
		Emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
		-- The 90 puts the stretched axis along the direction of travel. See the note on
		-- VelocityParallel in Spray's Simulation.luau.
		Emitter.Rotation = NumberRange.new(90)
		Emitter.RotSpeed = NumberRange.new(0)
		Emitter.Lifetime = NumberRange.new(0.35, 0.7)
		Emitter.Speed = NumberRange.new(3, 6.5)
		Emitter.SpreadAngle = Vector2.new(180, 180)
		Emitter.Drag = 4
		Emitter.Acceleration = Vector3.new(0, -6, 0)
		Emitter.Rate = 20
		Emitter.Enabled = false
		Emitter:SetAttribute("BurstCount", 28)
		Emitter:SetAttribute("SprayGlowLayers", 2)
	end,

	Flame = function(Emitter)
		Emitter.Texture = TEXTURE.Fireball
		Emitter.Color = Colors({ { 0, rgb(255, 244, 214) }, { 0.4, rgb(255, 176, 96) }, { 1, rgb(210, 70, 40) } })
		Emitter.LightEmission = 0.6
		Emitter.Brightness = 1.4
		Emitter.Size = Numbers({ { 0, 0.36, 0.05 }, { 1, 0.1 } })
		Emitter.Transparency = Numbers({ { 0, 1 }, { 0.1, 0.05 }, { 0.65, 0.35 }, { 1, 1 } })
		Emitter.Lifetime = NumberRange.new(0.55, 0.95)
		Emitter.Speed = NumberRange.new(0.7, 1.3)
		Emitter.SpreadAngle = Vector2.new(10, 10)
		Emitter.Acceleration = Vector3.new(0, 1.5, 0)
		Emitter.Drag = 1.2
		Emitter.Rotation = NumberRange.new(-40, 40)
		Emitter.RotSpeed = NumberRange.new(-90, 90)
		Emitter.Rate = 45
		Emitter.Enabled = true
		Emitter.Shape = Enum.ParticleEmitterShape.Box
		Emitter:SetAttribute("BurstCount", 0)
		Emitter:SetAttribute("SprayEmissionSize", Vector2.new(0.35, 0.08))
	end,

	Smoke = function(Emitter)
		Emitter.Texture = TEXTURE.Smoke
		Emitter.Color = Colors({ { 0, rgb(160, 165, 176) }, { 1, rgb(92, 97, 108) } })
		Emitter.LightEmission = 0
		Emitter.Brightness = 1
		Emitter.Size = Numbers({ { 0, 0.25 }, { 1, 0.85, 0.1 } })
		Emitter.Transparency = Numbers({ { 0, 1 }, { 0.2, 0.55 }, { 1, 1 } })
		Emitter.Lifetime = NumberRange.new(1.6, 2.6)
		Emitter.Speed = NumberRange.new(0.25, 0.55)
		Emitter.SpreadAngle = Vector2.new(25, 25)
		Emitter.Acceleration = Vector3.new(0, 0.35, 0)
		Emitter.Drag = 0.6
		Emitter.Rotation = NumberRange.new(0, 360)
		Emitter.RotSpeed = NumberRange.new(-25, 25)
		Emitter.Rate = 9
		Emitter.Enabled = true
		Emitter:SetAttribute("BurstCount", 0)
	end,

	["Implode Ring"] = function(Emitter)
		Emitter.Texture = TEXTURE.Sparkles
		Emitter.Color = Colors({ { 0, rgb(120, 255, 214) }, { 1, rgb(80, 140, 255) } })
		Emitter.LightEmission = 1
		Emitter.Brightness = 2
		Emitter.Size = Numbers({ { 0, 0 }, { 0.2, 0.1 }, { 1, 0.02 } })
		Emitter.Transparency = Numbers({ { 0, 1 }, { 0.15, 0 }, { 1, 0.3 } })
		Emitter.Lifetime = NumberRange.new(0.9, 1.1)
		Emitter.Speed = NumberRange.new(0.55, 0.65)
		Emitter.SpreadAngle = Vector2.zero
		Emitter.RotSpeed = NumberRange.new(0)
		Emitter.Shape = Enum.ParticleEmitterShape.Sphere
		Emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		Emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		Emitter.Rate = 70
		Emitter.Enabled = true
		Emitter:SetAttribute("BurstCount", 0)
		Emitter:SetAttribute("SprayEmissionSize", Vector2.new(1.6, 1.6))
	end,

	-- Untouched engine defaults. Big and fast at this scale, which is the point: it shows
	-- what "one stud is the parent's height" means before anything is tuned.
	["Roblox Default"] = function(Emitter)
		Emitter:SetAttribute("BurstCount", 0)
	end,
}

Presets.Names = { "Sparkle Burst", "Sparks", "Flame", "Smoke", "Implode Ring", "Roblox Default" }
Presets.Default = "Sparkle Burst"

function Presets.Build(Name: string): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = string.gsub(Name, "%s", "")
	local builder = BUILDERS[Name] or BUILDERS[Presets.Default]
	builder(emitter)
	return emitter
end

return Presets

--!strict
--!native
-->> Renderer.luau
--> Owns the ImageLabels. This is the only file in the package that touches Instances.
-->
--> LIGHT. Roblox GUI only has one blend mode (plain alpha blending), so LightEmission can't
--> be done for real because there's no additive mode to ask for. What we can do is fake
--> it, and this file does that in two ways at the same time:
-->
-->   1. Tone mapping, always on and basically free. Brightness above 1 pushes the colour
-->      past the top of the range, and a channel that clips can only head toward white. So
-->      the colour gets renormalised and pulled toward white by however far it overflowed.
-->      That gives you the blown-out core with a coloured edge that additive particles
-->      have, and it means Brightness 15 no longer has to be faked by baking the light
-->      into the texture.
-->   2. Halo layers, opt in with SprayGlowLayers. These are extra copies drawn behind the
-->      particle, each one bigger and fainter than the last, which reads as bloom around
-->      the core. They're scaled by LightEmission, so an emitter that doesn't emit light
-->      gets no halo.
-->
--> Neither of these makes two overlapping particles add up like real additive blending
--> would, and nothing a GuiObject can do will get you there. On the dark panels these
--> effects usually sit on the difference is small, and tone mapping covers most of it.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local Sampling = require(script.Parent.Sampling)
local Simulation = require(script.Parent.Simulation)
local Types = require(script.Parent.Types)

type Spec = Types.Spec
type ParticleFrame = Types.ParticleFrame
type Constants = Simulation.Constants

const WHITE = Color3.new(1, 1, 1)

--- Each halo ring after the core is this much bigger than the previous one and keeps this
--- fraction of its opacity. Tuned so three layers look like a glow and not like three
--- separate rings.
const HALO_GROWTH = 0.45
const HALO_FALLOFF = 0.45

--- What was last written to one ImageLabel. A property write costs far more than comparing
--- two numbers, so Draw skips every write that wouldn't change anything, which on an
--- emitter with a flat size, colour or rotation is most of them. Visibility is tracked here
--- too because reading it back from the label is a property read on every particle. Nil
--- means nothing has been written yet.
type Written = {
	Shown: boolean,
	X: number?,
	Y: number?,
	Width: number?,
	Height: number?,
	Rotation: number?,
	Transparency: number?,
	Color: Color3?,
}

--- The Instances for one particle, plus the constants that describe it. Slots get reused:
--- when a particle dies its slot goes to the next one, which is why the Constants table is
--- written into instead of replaced. Written survives the handover on purpose, since the
--- labels keep their properties too.
export type Slot = {
	Key: number,
	Pass: number, -- the last render pass that drew it (see Render in init.luau)
	Constants: Constants,
	Layers: { ImageLabel },
	Written: { Written },
}

export type Renderer = {
	Container: Frame,
	Spec: Spec,
	Slots: { Slot },
	Free: { Slot },
	Active: { [number]: Slot },
	FlatColor: Color3?,
	ClipHost: GuiObject?,
	InsetHost: boolean,
}

local Renderer = {}

-- -- Colour --------------------------------------------------------------------

--- Combines Brightness, LightEmission and LightInfluence into one Color3 that the
--- ImageLabel can actually use.
---
--- Brightness is the HDR gain and works on its own. LightEmission is a separate thing that
--- decides how additive the particle is, which here means how much halo it gets. It's
--- tempting to tie the two together, but that flattens every layer authored bright but NOT
--- light-emitting, and you won't notice until you look. A soft impact glow at Brightness 4
--- would come out as a plain mid-tone colour instead of the blown-out cream it should be.
local function Grade(Snapshot: Spec, Source: Color3): Color3
	local gain = math.max(Snapshot.Brightness, 0)
	if gain == 1 and Snapshot.LightInfluence <= 0 then
		return Source -- the usual case, and nothing to grade
	end

	local red, green, blue = Source.R * gain, Source.G * gain, Source.B * gain
	local peak = math.max(red, green, blue)

	local graded: Color3
	if peak > 1 then
		-- Renormalise, then pull toward white by however much got clipped. The brighter the
		-- colour, the whiter the core.
		graded = Color3.new(red / peak, green / peak, blue / peak):Lerp(WHITE, 1 - 1 / peak)
	else
		graded = Color3.new(red, green, blue)
	end

	if Snapshot.LightInfluence > 0 then
		-- A ScreenGui has no scene lighting, so the closest reasonable substitute is the
		-- ambient light the 3D emitter would have been sitting in.
		local ambient = Lighting.Ambient
		graded = graded:Lerp(
			Color3.new(graded.R * ambient.R, graded.G * ambient.G, graded.B * ambient.B),
			Snapshot.LightInfluence
		)
	end

	return graded
end

-- -- Construction --------------------------------------------------------------

--- The GuiObject the pool hangs from. Usually that's the emitter's own parent, but with
--- SprayIgnoreClips it climbs past anything that would clip the particles at its edges.
local function ResolveHost(Snapshot: Spec): (Instance, GuiObject?, boolean)
	if not Snapshot.IgnoreClips then
		return Snapshot.Parent, nil, false
	end

	local host: Instance = Snapshot.Parent
	while host:IsA("GuiObject") do
		local above = host.Parent
		if not above then
			break
		end
		if above:IsA("LayerCollector") then
			local usesInset = above:IsA("ScreenGui") and not above.IgnoreGuiInset
			return above, nil, usesInset
		end
		host = above
	end

	if host:IsA("GuiObject") then
		return host, host, false
	end
	return Snapshot.Parent, nil, false
end

function Renderer.New(Snapshot: Spec): Renderer
	local host, clipHost, insetHost = ResolveHost(Snapshot)

	local container = Instance.new("Frame")
	container.Name = "Spray_" .. Snapshot.Emitter.Name
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = false
	container.ZIndex = Snapshot.ZIndexBase
	-- A zero-size frame pinned to the centre of the parent. Every particle is positioned
	-- with a pixel offset from it, so the container's size never matters.
	container.AnchorPoint = Vector2.zero
	container.Size = UDim2.fromOffset(0, 0)
	container.Position = UDim2.fromScale(0.5, 0.5)
	-- The pool is runtime state. Cloning the UI it lives in shouldn't copy a stale one, and
	-- a place saved while a Studio preview is drawing shouldn't keep it forever.
	container.Archivable = false
	container.Parent = host

	return {
		Container = container,
		Spec = Snapshot,
		Slots = {},
		Free = {},
		Active = {},
		FlatColor = if Sampling.IsFlatColor(Snapshot.Color) then Grade(Snapshot, Snapshot.Color[1].Value) else nil,
		ClipHost = clipHost,
		InsetHost = insetHost,
	}
end

--- Creates the Instances for one particle. Anything that never changes gets set here, so
--- the per-frame code only writes what actually moves.
local function BuildSlot(Self: Renderer): Slot
	local snapshot = Self.Spec
	local layers = table.create(snapshot.GlowLayers)
	local written = table.create(snapshot.GlowLayers)

	-- A flipbook cell always has the same SIZE, only its position changes. So the crop
	-- size is set once, here, and the per-frame code only touches the offset. That saves
	-- one property write per particle per frame, and it also avoids an engine quirk where
	-- an ImageRectSize set right alongside an ImageRectOffset of (0, 0) doesn't stick. That
	-- quirk showed up as the first cell of a flipbook rendering as the entire sheet.
	local edge = if snapshot.FlipbookFrames > 0 then snapshot.FlipbookResolution / snapshot.FlipbookFrames else 0

	for index = 1, snapshot.GlowLayers do
		local label = Instance.new("ImageLabel")
		label.Name = "Particle"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Image = snapshot.Texture
		label.ResampleMode = snapshot.ResampleMode
		label.ScaleType = Enum.ScaleType.Stretch
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Visible = false
		if edge > 0 then
			label.ImageRectSize = Vector2.new(edge, edge)
		end
		-- ZOffset is the emitter's depth in 3D, and here it becomes the ZIndex. Each halo
		-- ring sits one step further back than the last, so none of them covers the core.
		label.ZIndex = snapshot.ZIndexBase + math.round(snapshot.ZOffset) - (index - 1)
		label.Parent = Self.Container
		layers[index] = label
		written[index] = { Shown = false }
	end

	return {
		Key = -1,
		Pass = 0,
		Constants = {
			Key = -1, SpawnTime = 0, Lifetime = 1,
			OffsetX = 0, OffsetY = 0,
			VelocityX = 0, VelocityY = 0,
			Rotation = 0, RotationSpeed = 0,
			SizeRoll = 0, TransparencyRoll = 0, SquashRoll = 0,
			FlipbookStart = 1, FlipbookRate = 1,
		} :: Constants,
		Layers = layers,
		Written = written,
	}
end

-- -- Slot lifecycle ------------------------------------------------------------

--- Returns the slot that already holds `Key`, or a free one, or nil once the emitter has
--- hit its limit. A reused slot still has the previous particle's constants in it. The
--- caller notices because the Key doesn't match, and derives them again.
function Renderer.Acquire(Self: Renderer, Key: number): Slot?
	local existing = Self.Active[Key]
	if existing then
		return existing
	end

	local recycled = table.remove(Self.Free)
	local claimed: Slot
	if recycled then
		claimed = recycled
	else
		if #Self.Slots >= Self.Spec.MaxParticles then
			return nil
		end
		claimed = BuildSlot(Self)
		table.insert(Self.Slots, claimed)
	end

	claimed.Key = Key
	Self.Active[Key] = claimed
	return claimed
end

--- Puts a slot away. Its Instances stay where they are, just hidden, ready for the next
--- particle. Rebuilding them every time is what made the old library stutter on the first
--- burst after sitting idle.
function Renderer.Release(Self: Renderer, Slot: Slot)
	Self.Active[Slot.Key] = nil
	Slot.Key = -1
	for index, label in Slot.Layers do
		local written = Slot.Written[index]
		if written.Shown then
			label.Visible = false
			written.Shown = false
		end
	end
	table.insert(Self.Free, Slot)
end

--- Builds slots ahead of time, hidden and waiting in the pool, so the bursts that come
--- later don't create Instances in the middle of a frame. Creating the ImageLabels is most
--- of what the very first burst of an effect costs. Never builds past SprayMaxParticles,
--- and counts the slots that already exist.
function Renderer.Prewarm(Self: Renderer, Count: number)
	local target = math.min(math.floor(Count), Self.Spec.MaxParticles)
	for _ = #Self.Slots + 1, target do
		local slot = BuildSlot(Self)
		table.insert(Self.Slots, slot)
		table.insert(Self.Free, slot)
	end
end

function Renderer.ReleaseAll(Self: Renderer)
	for _, slot in Self.Active do
		Renderer.Release(Self, slot)
	end
	table.clear(Self.Active)
end

-- -- Drawing ------------------------------------------------------------------

--- Writes one resolved particle onto its Instances, skipping every property that already
--- holds the value it would get (see Written).
function Renderer.Draw(Self: Renderer, Slot: Slot, Frame: ParticleFrame)
	local snapshot = Self.Spec

	local flat = Self.FlatColor
	local color: Color3 = if flat then flat else Grade(snapshot, Frame.Color)

	local haloStrength = snapshot.LightEmission
	local layers = Slot.Layers
	local writtenLayers = Slot.Written
	local x, y, rotation = Frame.X, Frame.Y, Frame.Rotation

	for index = 1, #layers do
		local label = layers[index]
		local written = writtenLayers[index]

		local width, height = Frame.Width, Frame.Height
		local transparency = Frame.Transparency

		if index > 1 then
			local step = index - 1
			local growth = 1 + HALO_GROWTH * step
			width *= growth
			height *= growth
			-- Fade the ring, then fade it again based on how much light the emitter says it
			-- gives off. With LightEmission at 0 there's no halo at all.
			local opacity = (1 - transparency) * (HALO_FALLOFF ^ step) * haloStrength
			transparency = 1 - opacity
		end

		if transparency >= 1 or width <= 0 or height <= 0 then
			if written.Shown then
				label.Visible = false
				written.Shown = false
			end
			continue
		end

		-- Made visible BEFORE anything else is written to it, because a hidden ImageLabel
		-- ignores ImageRectSize. Otherwise a flipbook particle whose first drawn frame is
		-- also its first visible frame would never get its crop and would show the whole
		-- sheet. Everything else on the label is set in this same frame, so nothing shows
		-- up on screen before it's been positioned.
		if not written.Shown then
			label.Visible = true
			written.Shown = true
		end

		if written.X ~= x or written.Y ~= y then
			label.Position = UDim2.fromOffset(x, y)
			written.X, written.Y = x, y
		end
		if written.Width ~= width or written.Height ~= height then
			label.Size = UDim2.fromOffset(width, height)
			written.Width, written.Height = width, height
		end
		if written.Rotation ~= rotation then
			label.Rotation = rotation
			written.Rotation = rotation
		end
		if written.Transparency ~= transparency then
			label.ImageTransparency = transparency
			written.Transparency = transparency
		end
		if written.Color ~= color then
			label.ImageColor3 = color
			written.Color = color
		end

		-- Only the offset really changes, but the size is written again with it instead of
		-- trusting the value from BuildSlot. The engine ignores an ImageRectSize set on a
		-- texture it hasn't finished loading, and there's no way to check whether it
		-- stuck, so we set the crop again every time. It costs one extra property write,
		-- and only on flipbook emitters.
		--
		-- The one case this can't fix is a particle whose first VISIBLE frame is also the
		-- first frame its slot exists. The texture might still be loading, so that frame
		-- shows the whole sheet before it corrects itself. Since slots are pooled and
		-- reused, this can only happen on the very first burst after a Spray is built.
		if Frame.RectSize > 0 then
			label.ImageRectOffset = Vector2.new(Frame.RectOffsetX, Frame.RectOffsetY)
			label.ImageRectSize = Vector2.new(Frame.RectSize, Frame.RectSize)
		end
	end
end

--- Keeps a hoisted container sitting over the emitter's origin. It only does anything when
--- SprayIgnoreClips moved the pool out of its natural parent. Otherwise the nesting already
--- keeps the two lined up.
function Renderer.Follow(Self: Renderer)
	if not Self.Spec.IgnoreClips then
		return
	end

	local parent = Self.Spec.Parent
	local origin = parent.AbsolutePosition + parent.AbsoluteSize * 0.5

	local clipHost = Self.ClipHost
	if clipHost then
		origin -= clipHost.AbsolutePosition
	elseif Self.InsetHost then
		origin -= GuiService:GetGuiInset()
	end

	Self.Container.Position = UDim2.fromOffset(origin.X, origin.Y)
	Self.Container.Rotation = parent.AbsoluteRotation
end

function Renderer.Destroy(Self: Renderer)
	Self.Container:Destroy()
	table.clear(Self.Slots)
	table.clear(Self.Free)
	table.clear(Self.Active)
end

return Renderer

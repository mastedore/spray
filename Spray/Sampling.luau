--!strict
--!native
-->> Sampling.luau
--> The two building blocks the simulation uses: a hash-based random and a sequence reader.
-->
--> Both are STATELESS on purpose. A Spray has to be able to jump its clock to any point,
--> forwards or backwards, and end up with exactly the particles it would have had by
--> playing there frame by frame. A stateful generator can't do that, because you can only
--> ask it for the next number and never for the 400th. So the random here is a hash, which
--> means the same (seed, index, channel) always gives back the same number, in any order.
--> The sequence reader is stateless for the same reason. The old library cached "which
--> keypoint am I on" for each particle, which is faster while time only moves forward but
--> breaks as soon as it goes backwards.
-->
--> The sequences it reads are curves, plain tables made once from the engine's
--> NumberSequence and ColorSequence by NumberCurve and ColorCurve. Types.luau says why.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local Types = require(script.Parent.Types)

type NumberCurve = Types.NumberCurve
type ColorCurve = Types.ColorCurve

const MASK32 = 0xFFFFFFFF
const NORMALIZE = 1 / 4294967296

local Sampling = {}

-- -- Hash random ---------------------------------------------------------------

--- 32-bit wrapping multiply. Doing it the naive way overflows the 53-bit mantissa of a
--- double and drops the low bits without any error, and you only notice because particles
--- start clumping together. So the operands get split into 16-bit halves and recombined.
local function Multiply32(a: number, b: number): number
	local aHigh, aLow = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	local bHigh, bLow = bit32.rshift(b, 16), bit32.band(b, 0xFFFF)
	local cross = bit32.band(aHigh * bLow + aLow * bHigh, 0xFFFF)
	return bit32.band(bit32.lshift(cross, 16) + aLow * bLow, MASK32)
end

--- The finalizer from splitmix32. It's cheap and mixes the bits well enough that
--- neighbouring particle indices end up with completely unrelated values.
local function Mix32(value: number): number
	local z = bit32.band(value + 0x9E3779B9, MASK32)
	z = Multiply32(bit32.bxor(z, bit32.rshift(z, 16)), 0x21F0AAAD)
	z = Multiply32(bit32.bxor(z, bit32.rshift(z, 15)), 0x735A2D97)
	return bit32.bxor(z, bit32.rshift(z, 15))
end

--- The half of the hash that depends only on the seed and the particle. Every roll a
--- particle makes starts from it, so Derive mixes it once and reuses it for the dozen or so
--- channels it rolls instead of mixing it again for each one, which halves what spawning a
--- particle costs.
function Sampling.Stream(Seed: number, Index: number): number
	return Mix32(bit32.bxor(bit32.band(Seed, MASK32), Multiply32(Index + 1, 0x9E3779B1)))
end

--- A number in [0, 1) that depends only on its inputs. `Stream` is the particle (from
--- Stream) and `Channel` is which of its properties is being rolled. Speed, lifetime, spawn
--- angle and the rest each get their own channel, so changing one emitter property doesn't
--- reshuffle every other roll the particle made.
function Sampling.Unit(Stream: number, Channel: number): number
	return Mix32(bit32.bxor(Stream, Multiply32(Channel + 1, 0x85EBCA77))) * NORMALIZE
end

--- Same thing, mapped to [-1, 1). Used for NumberSequence envelopes.
function Sampling.Signed(Stream: number, Channel: number): number
	return Sampling.Unit(Stream, Channel) * 2 - 1
end

--- Picks a value from a NumberRange.
function Sampling.Range(Stream: number, Channel: number, Range: NumberRange): number
	if Range.Min == Range.Max then
		return Range.Min
	end
	return Range.Min + (Range.Max - Range.Min) * Sampling.Unit(Stream, Channel)
end

--- A whole number in [Low, High]. Used to pick flipbook frames.
function Sampling.Integer(Stream: number, Channel: number, Low: number, High: number): number
	if High <= Low then
		return Low
	end
	return Low + math.floor(Sampling.Unit(Stream, Channel) * (High - Low + 1))
end

-- -- Sequences -----------------------------------------------------------------

function Sampling.NumberCurve(Sequence: NumberSequence): NumberCurve
	local curve = {}
	for index, keypoint in Sequence.Keypoints do
		curve[index] = table.freeze({
			Time = keypoint.Time,
			Value = keypoint.Value,
			Envelope = keypoint.Envelope,
		})
	end
	return table.freeze(curve)
end

function Sampling.ColorCurve(Sequence: ColorSequence): ColorCurve
	local curve = {}
	for index, keypoint in Sequence.Keypoints do
		curve[index] = table.freeze({
			Time = keypoint.Time,
			Value = keypoint.Value,
		})
	end
	return table.freeze(curve)
end

--- Reads a number curve at `Time` (0..1).
---
--- `EnvelopeRoll` is the particle's own value in [-1, 1]. It stays the same for the
--- particle's whole life, which is why an envelope looks like variation between particles
--- and not like noise that changes every frame.
function Sampling.Number(Curve: NumberCurve, Time: number, EnvelopeRoll: number): number
	local count = #Curve

	if count == 1 or Time <= 0 then
		local first = Curve[1]
		return first.Value + first.Envelope * EnvelopeRoll
	end
	if Time >= 1 then
		local last = Curve[count]
		return last.Value + last.Envelope * EnvelopeRoll
	end

	-- Roblox limits sequences to 20 keypoints, so a plain scan is faster than a binary
	-- search here.
	for index = 1, count - 1 do
		local current = Curve[index]
		local following = Curve[index + 1]
		if Time <= following.Time then
			local span = following.Time - current.Time
			local alpha = if span > 0 then (Time - current.Time) / span else 0
			local value = current.Value + (following.Value - current.Value) * alpha
			local envelope = current.Envelope + (following.Envelope - current.Envelope) * alpha
			return value + envelope * EnvelopeRoll
		end
	end

	local last = Curve[count]
	return last.Value + last.Envelope * EnvelopeRoll
end

--- Reads a colour curve at `Time` (0..1). Colour keypoints have no envelope, so there's
--- nothing to roll per particle.
function Sampling.Color(Curve: ColorCurve, Time: number): Color3
	local count = #Curve

	if count == 1 or Time <= 0 then
		return Curve[1].Value
	end
	if Time >= 1 then
		return Curve[count].Value
	end

	for index = 1, count - 1 do
		local current = Curve[index]
		local following = Curve[index + 1]
		if Time <= following.Time then
			local span = following.Time - current.Time
			local alpha = if span > 0 then (Time - current.Time) / span else 0
			return current.Value:Lerp(following.Value, alpha)
		end
	end

	return Curve[count].Value
end

--- True when every keypoint has the same value, which lets the renderer skip one write per
--- particle per frame. Most emitters use a single flat Color, so it's worth checking.
function Sampling.IsFlatColor(Curve: ColorCurve): boolean
	local first = Curve[1].Value
	for index = 2, #Curve do
		if Curve[index].Value ~= first then
			return false
		end
	end
	return true
end

return Sampling

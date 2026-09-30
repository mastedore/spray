-->> Simulation.spec.luau
--> The closed-form physics and the per-particle rolls. Every case checks a number that can
--> be worked out on paper from the emitter in Helpers.Emitter: a point source firing
--> straight up at 100 px/s, particles 10 px across that live exactly one second.

return function()
	local Helpers = require(script.Parent.Helpers)
	local Sampling = require(Helpers.Package.Sampling)
	local Simulation = require(Helpers.Package.Simulation)
	local Spec = require(Helpers.Package.Spec)

	const SEED = 12345
	const KEY = 7

	local function Snapshot(Properties: { [string]: any }?, Attributes: { [string]: any }?): any
		local frame = Instance.new("Frame")
		local emitter = Helpers.Emitter(Properties, Attributes)
		emitter.Parent = frame
		return Spec.Read(emitter)
	end

	--- A snapshot with fields the engine would never let an emitter hold (negative drag,
	--- out of range transparency) patched in directly.
	local function Patched(Fields: { [string]: any }, Properties: { [string]: any }?): any
		local copy = table.clone(Snapshot(Properties))
		for name, value in Fields do
			copy[name] = value
		end
		return copy
	end

	local function Derive(Snap: any, Key: number?, SpawnTime: number?): any
		local constants = {}
		Simulation.Derive(Snap, SEED, Key or KEY, SpawnTime or 0, constants)
		return constants
	end

	--- Resolves a particle spawned at 0 at `Age`, at one pixel per stud. Returns the frame
	--- and whether the particle was alive.
	local function Resolve(Snap: any, Age: number, Key: number?): (any, boolean)
		local frame = {}
		local alive = Simulation.Resolve(Snap, Derive(Snap, Key), SEED, Age, 1, 200, 100, frame)
		return frame, alive
	end

	describe("lifetime", function()
		it("is not alive before it spawns or once its lifetime is up", function()
			local snap = Snapshot()
			local constants = Derive(snap, KEY, 2)
			local frame = {}
			expect(Simulation.Resolve(snap, constants, SEED, 1.99, 1, 200, 100, frame)).to.equal(false)
			expect(Simulation.Resolve(snap, constants, SEED, 2, 1, 200, 100, frame)).to.equal(true)
			expect(Simulation.Resolve(snap, constants, SEED, 2.99, 1, 200, 100, frame)).to.equal(true)
			expect(Simulation.Resolve(snap, constants, SEED, 3, 1, 200, 100, frame)).to.equal(false)
		end)

		it("bounds the search by the longest possible lifetime", function()
			expect(Simulation.MaximumLifetime(Snapshot({ Lifetime = NumberRange.new(0.5, 3) }))).to.equal(3)
		end)
	end)

	describe("motion", function()
		it("moves at constant velocity with no drag or acceleration", function()
			local frame = Resolve(Snapshot(), 0.5)
			expect(frame.X).to.be.near(0, 1e-6)
			expect(frame.Y).to.be.near(-50, 1e-6)
		end)

		it("falls under gravity as v*t + a*t^2/2", function()
			-- -40 studs/s^2 in 3D is 40 px/s^2 DOWN the screen.
			local frame = Resolve(Snapshot({ Speed = NumberRange.new(0), Acceleration = Vector3.new(0, -40, 0) }), 0.5)
			expect(frame.Y).to.be.near(5, 1e-6)
		end)

		it("decays velocity exponentially under drag", function()
			local frame = Resolve(Snapshot({ Drag = 2 }), 0.5)
			expect(frame.Y).to.be.near(-100 * (1 - math.exp(-1)) / 2, 1e-4)
		end)

		it("agrees with the drag-free branch as drag goes to zero", function()
			local without = Resolve(Patched({ Drag = 0 }, { Acceleration = Vector3.new(0, -40, 0) }), 0.8)
			local barely = Resolve(Patched({ Drag = 1e-3 }, { Acceleration = Vector3.new(0, -40, 0) }), 0.8)
			expect(barely.Y).to.be.near(without.Y, 0.1)
		end)

		it("settles on the terminal velocity a/k", function()
			local snap = Snapshot({ Speed = NumberRange.new(0), Acceleration = Vector3.new(0, -30, 0), Drag = 3, Lifetime = NumberRange.new(20) })
			local early = Resolve(snap, 10)
			local later = Resolve(snap, 11)
			expect(later.Y - early.Y).to.be.near(10, 1e-3)
		end)

		it("stays finite with negative drag", function()
			local frame = Resolve(Patched({ Drag = -80 }), 0.9)
			expect(frame.Y == frame.Y).to.equal(true) -- not NaN
			expect(math.abs(frame.Y) < math.huge).to.equal(true)
		end)

		it("scales travel by SprayScale", function()
			local frame = Resolve(Snapshot(nil, { SprayScale = 2 }), 0.5)
			expect(frame.Y).to.be.near(-100, 1e-6)
		end)
	end)

	describe("spread and emission area", function()
		it("keeps every particle inside the spread cone", function()
			local snap = Snapshot({ SpreadAngle = Vector2.new(30, 30) })
			for key = 0, 200 do
				local constants = Derive(snap, key)
				local angle = math.deg(math.acos(math.clamp(-constants.VelocityY / 100, -1, 1)))
				expect(angle <= 30 + 1e-4).to.equal(true)
			end
		end)

		it("gives different particles different directions, and the same particle the same one", function()
			local snap = Snapshot({ SpreadAngle = Vector2.new(180, 180) })
			expect(Derive(snap, 1).VelocityX).to.equal(Derive(snap, 1).VelocityX)
			expect(Derive(snap, 1).VelocityX).never.to.equal(Derive(snap, 2).VelocityX)
		end)

		it("fills a box emission area and nothing outside it", function()
			local snap = Snapshot({ Shape = Enum.ParticleEmitterShape.Box }, { SprayEmissionSize = Vector2.new(1, 0.5) })
			for key = 0, 200 do
				local constants = Derive(snap, key)
				expect(math.abs(constants.OffsetX) <= 0.5).to.equal(true)
				expect(math.abs(constants.OffsetY) <= 0.25).to.equal(true)
			end
		end)

		it("puts sphere surface particles on the ellipse", function()
			local snap = Snapshot({
				Shape = Enum.ParticleEmitterShape.Sphere,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			}, { SprayEmissionSize = Vector2.new(1, 0.5) })
			for key = 0, 50 do
				local constants = Derive(snap, key)
				local radius = (constants.OffsetX / 0.5) ^ 2 + (constants.OffsetY / 0.25) ^ 2
				expect(radius).to.be.near(1, 1e-6)
			end
		end)

		it("fires inward when ShapeInOut is Inward", function()
			local snap = Snapshot({
				Shape = Enum.ParticleEmitterShape.Sphere,
				ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
				ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			}, { SprayEmissionSize = Vector2.new(1, 1) })
			for key = 0, 50 do
				local constants = Derive(snap, key)
				local outward = constants.OffsetX * constants.VelocityX + constants.OffsetY * constants.VelocityY
				expect(outward < 0).to.equal(true)
			end
		end)
	end)

	describe("size", function()
		it("draws Size in studs, times SpraySizeScale", function()
			local frame = Resolve(Snapshot(nil, { SpraySizeScale = 1.5 }), 0.2)
			expect(frame.Width).to.be.near(15, 1e-6)
			expect(frame.Height).to.be.near(15, 1e-6)
		end)

		it("squashes while keeping the area", function()
			local tall = Resolve(Snapshot({ Squash = NumberSequence.new(1) }), 0.2)
			expect(tall.Width).to.be.near(5, 1e-6)
			expect(tall.Height).to.be.near(20, 1e-6)

			local wide = Resolve(Snapshot({ Squash = NumberSequence.new(-1) }), 0.2)
			expect(wide.Width).to.be.near(20, 1e-6)
			expect(wide.Height).to.be.near(5, 1e-6)
		end)

		it("clamps transparency to [0, 1]", function()
			local frame = Resolve(Patched({ Transparency = Sampling.NumberCurve(NumberSequence.new(1.5)) }), 0.2)
			expect(frame.Transparency).to.equal(1)
		end)
	end)

	describe("rotation", function()
		it("spins at RotSpeed from Rotation when facing the camera", function()
			local frame = Resolve(Snapshot({ Rotation = NumberRange.new(30), RotSpeed = NumberRange.new(90) }), 0.5)
			expect(frame.Rotation).to.be.near(75, 1e-6)
		end)

		-- A streak texture is drawn vertically and authored as VelocityParallel with
		-- Rotation 90. Its long axis must end up along the direction of travel.
		local function Axis(Rotation: number): number
			local folded = Rotation % 180
			return math.min(folded, 180 - folded)
		end

		it("lines a VelocityParallel streak up with vertical travel", function()
			local frame = Resolve(Snapshot({
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Rotation = NumberRange.new(90),
			}), 0.3)
			expect(Axis(frame.Rotation)).to.be.near(0, 1e-4)
		end)

		it("lines a VelocityParallel streak up with horizontal travel", function()
			local frame = Resolve(Snapshot({
				Orientation = Enum.ParticleOrientation.VelocityParallel,
				Rotation = NumberRange.new(90),
				EmissionDirection = Enum.NormalId.Right,
			}), 0.3)
			expect(Axis(frame.Rotation)).to.be.near(90, 1e-4)
		end)
	end)

	describe("flipbook", function()
		it("walks a OneShot grid across the particle's life", function()
			local snap = Snapshot({
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			})
			local first = Resolve(snap, 0)
			expect(first.RectSize).to.equal(256)
			expect(first.RectOffsetX).to.equal(0)
			expect(first.RectOffsetY).to.equal(0)

			local last = Resolve(snap, 0.999)
			expect(last.RectOffsetX).to.equal(768)
			expect(last.RectOffsetY).to.equal(768)
		end)

		it("advances a Loop grid at the framerate", function()
			local frame = Resolve(Snapshot({
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.Loop,
				FlipbookFramerate = NumberRange.new(4),
			}), 0.5)
			-- Two frames in at 4 fps: cell 3, the third one along the top row.
			expect(frame.RectOffsetX).to.equal(512)
			expect(frame.RectOffsetY).to.equal(0)
		end)

		it("shows the same Random cell every time the same moment is drawn", function()
			local snap = Snapshot({
				FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
				FlipbookMode = Enum.ParticleFlipbookMode.Random,
				FlipbookFramerate = NumberRange.new(10),
			})
			for age = 0, 0.9, 0.1 do
				local a, b = Resolve(snap, age), Resolve(snap, age)
				expect(a.RectOffsetX).to.equal(b.RectOffsetX)
				expect(a.RectOffsetY).to.equal(b.RectOffsetY)
			end
		end)

		it("reports no crop without a flipbook", function()
			expect(Resolve(Snapshot(), 0.5).RectSize).to.equal(0)
		end)
	end)
end

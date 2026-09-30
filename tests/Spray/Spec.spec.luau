-->> Spec.spec.luau
--> Reading an emitter into a snapshot: the 2D translation of 3D properties, the Spray*
--> attributes and their defaults, and the stud-to-pixel conversion.

return function()
	local Helpers = require(script.Parent.Helpers)
	local Spec = require(Helpers.Package.Spec)

	--- An emitter under a Frame that is NOT in the DataModel. Reading a spec does not need
	--- the tree, only a GuiObject ancestor.
	local function Read(Properties: { [string]: any }?, Attributes: { [string]: any }?)
		local frame = Instance.new("Frame")
		frame.ZIndex = 7
		local emitter = Helpers.Emitter(Properties, Attributes)
		emitter.Parent = frame
		return Spec.Read(emitter), emitter, frame
	end

	describe("Read", function()
		it("refuses an emitter with no GuiObject above it", function()
			local emitter = Instance.new("ParticleEmitter")
			expect(function()
				Spec.Read(emitter)
			end).to.throw()
		end)

		it("finds the GuiObject through a Folder", function()
			local frame = Instance.new("Frame")
			local folder = Instance.new("Folder")
			folder.Parent = frame
			local emitter = Helpers.Emitter()
			emitter.Parent = folder
			expect(Spec.Read(emitter).Parent).to.equal(frame)
		end)

		it("returns a frozen table", function()
			local snapshot = Read()
			expect(table.isfrozen(snapshot)).to.equal(true)
		end)

		it("flips acceleration into GUI space, where +Y is down", function()
			local snapshot = Read({ Acceleration = Vector3.new(3, -9.8, 4) })
			expect(snapshot.Acceleration.X).to.be.near(3, 1e-6)
			expect(snapshot.Acceleration.Y).to.be.near(9.8, 1e-6)
		end)

		it("turns EmissionDirection into a screen vector", function()
			expect(Read({ EmissionDirection = Enum.NormalId.Top }).EmissionDirection).to.equal(Vector2.new(0, -1))
			expect(Read({ EmissionDirection = Enum.NormalId.Bottom }).EmissionDirection).to.equal(Vector2.new(0, 1))
			expect(Read({ EmissionDirection = Enum.NormalId.Right }).EmissionDirection).to.equal(Vector2.new(1, 0))
			expect(Read({ EmissionDirection = Enum.NormalId.Left }).EmissionDirection).to.equal(Vector2.new(-1, 0))
			expect(Read({ EmissionDirection = Enum.NormalId.Front }).EmissionDirection).to.equal(Vector2.new(0, -1))
		end)

		it("uses the X half of SpreadAngle, unsigned", function()
			expect(Read({ SpreadAngle = Vector2.new(-35, 90) }).SpreadAngle).to.equal(35)
		end)

		it("counts flipbook rows from the layout", function()
			expect(Read({ FlipbookLayout = Enum.ParticleFlipbookLayout.None }).FlipbookFrames).to.equal(0)
			expect(Read({ FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2 }).FlipbookFrames).to.equal(2)
			expect(Read({ FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4 }).FlipbookFrames).to.equal(4)
			expect(Read({ FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8 }).FlipbookFrames).to.equal(8)
		end)

		it("takes a Custom flipbook's rows from SprayFlipbookGrid", function()
			local custom = { FlipbookLayout = Enum.ParticleFlipbookLayout.Custom }
			expect(Read(custom).FlipbookFrames).to.equal(4)
			expect(Read(custom, { SprayFlipbookGrid = 6 }).FlipbookFrames).to.equal(6)
		end)
	end)

	describe("attributes", function()
		it("falls back to the defaults when none are set", function()
			local frame = Instance.new("Frame")
			frame.ZIndex = 3
			local emitter = Instance.new("ParticleEmitter")
			emitter.Parent = frame
			local snapshot = Spec.Read(emitter)

			expect(snapshot.SizeScale).to.equal(1)
			expect(snapshot.SpeedScale).to.equal(1)
			expect(snapshot.UnitMode).to.equal("RelativeYY")
			expect(snapshot.ZIndexBase).to.equal(3)
			expect(snapshot.MaxParticles).to.equal(400)
			expect(snapshot.GlowLayers).to.equal(1)
			expect(snapshot.EmissionSize).to.equal(Vector2.zero)
			expect(snapshot.FlipbookResolution).to.equal(1024)
			expect(snapshot.IgnoreClips).to.equal(false)
			expect(snapshot.Prewarm).to.equal(0)
		end)

		it("multiplies SprayScale into both size and speed", function()
			local snapshot = Read(nil, { SprayScale = 2, SpraySizeScale = 3, SpraySpeedScale = 0.5 })
			expect(snapshot.SizeScale).to.equal(6)
			expect(snapshot.SpeedScale).to.equal(1)
		end)

		it("ignores an attribute of the wrong type", function()
			local snapshot = Read(nil, { SprayScale = "huge", SprayMaxParticles = true })
			expect(snapshot.SizeScale).to.equal(1)
			expect(snapshot.MaxParticles).to.equal(400)
		end)

		it("ignores an unknown SprayUnit", function()
			expect(Read(nil, { SprayUnit = "Furlongs" }).UnitMode).to.equal("RelativeYY")
			expect(Read(nil, { SprayUnit = "RelativeMax" }).UnitMode).to.equal("RelativeMax")
		end)

		it("clamps SprayGlowLayers to 1..8 and SprayMaxParticles to at least 1", function()
			expect(Read(nil, { SprayGlowLayers = 50 }).GlowLayers).to.equal(8)
			expect(Read(nil, { SprayGlowLayers = 0 }).GlowLayers).to.equal(1)
			expect(Read(nil, { SprayMaxParticles = 0 }).MaxParticles).to.equal(1)
			expect(Read(nil, { SprayMaxParticles = 12.7 }).MaxParticles).to.equal(12)
		end)

		it("uses SprayZIndex over the parent's ZIndex", function()
			expect(Read().ZIndexBase).to.equal(7)
			expect(Read(nil, { SprayZIndex = 20 }).ZIndexBase).to.equal(20)
		end)
	end)

	describe("PixelsPerStud", function()
		-- Only Parent.AbsoluteSize and UnitMode are read, so a stand-in table will do.
		local function Measure(Mode: string): number
			return Spec.PixelsPerStud({
				Parent = { AbsoluteSize = Vector2.new(200, 100) },
				UnitMode = Mode,
			} :: any)
		end

		it("measures one stud against the requested edge", function()
			expect(Measure("RelativeYY")).to.equal(100)
			expect(Measure("RelativeXX")).to.equal(200)
			expect(Measure("RelativeMin")).to.equal(100)
			expect(Measure("RelativeMax")).to.equal(200)
			expect(Measure("Offset")).to.equal(1)
		end)
	end)
end

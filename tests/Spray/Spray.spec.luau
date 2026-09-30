-->> Spray.spec.luau
--> The public object, end to end: what ends up on screen after each call. Nothing here
--> waits for a frame - every method that moves the clock also draws - so the scheduler
--> never gets a say, and each test pauses before it finishes.

return function()
	local Helpers = require(script.Parent.Helpers)
	local Spray = require(Helpers.Package)

	local gui: ScreenGui
	local host: Frame
	local extras: { Instance }
	local effects: { any }

	--- A Spray over a fresh Helpers.Emitter in `Host` (the shared host by default).
	local function Make(Properties: { [string]: any }?, Attributes: { [string]: any }?, Host: Frame?)
		local emitter = Helpers.Emitter(Properties, Attributes)
		emitter.Parent = Host or host
		local effect = Spray.New(emitter)
		table.insert(effects, effect)
		return effect, emitter
	end

	--- A second host, for tests that compare two effects frame for frame.
	local function OtherHost(): Frame
		local otherGui, otherHost = Helpers.Host()
		table.insert(extras, otherGui)
		return otherHost
	end

	local function Seeded(Effect: any, Seed: number)
		Effect:UseRandom(false)
		Effect:RandomSeed(Seed)
	end

	local function Count(Host: Frame?): number
		return #Helpers.Visible(Host or host)
	end

	beforeEach(function()
		gui, host = Helpers.Host()
		extras = {}
		effects = {}
	end)

	afterEach(function()
		for _, effect in effects do
			pcall(function()
				effect:Destroy()
			end)
		end
		for _, extra in extras do
			extra:Destroy()
		end
		gui:Destroy()
	end)

	describe("New", function()
		it("only takes a ParticleEmitter", function()
			expect(function()
				Spray.New(Instance.new("Part") :: any)
			end).to.throw()
		end)

		it("starts paused with nothing on screen", function()
			Make()
			expect(Count()).to.equal(0)
			expect(host:FindFirstChild("Spray_Probe")).to.be.ok()
		end)
	end)

	describe("Emit", function()
		it("draws the requested number of particles", function()
			local effect = Make()
			effect:Emit(12)
			effect:Pause()
			expect(Count()).to.equal(12)
		end)

		it("caps a burst at SprayMaxParticles", function()
			local effect = Make(nil, { SprayMaxParticles = 5 })
			effect:Emit(50)
			effect:Pause()
			expect(Count()).to.equal(5)
		end)

		it("stacks onto a running effect", function()
			local effect = Make()
			effect:Emit(5)
			effect:Emit(3)
			effect:Pause()
			expect(Count()).to.equal(8)
		end)

		it("starts over when the effect is paused", function()
			local effect = Make()
			effect:Emit(5)
			effect:Pause()
			effect:SetTime(0.5)
			effect:Emit(3)
			effect:Pause()
			expect(Count()).to.equal(3)
			-- And the clock went back to zero: the new burst is still at the origin.
			for _, label in Helpers.Visible(host) do
				expect(label.Position.Y.Offset).to.be.near(0, 1e-6)
			end
		end)
	end)

	describe("the clock", function()
		it("puts a particle where the physics says", function()
			local effect = Make()
			effect:Emit(1)
			effect:Pause()
			effect:SetTime(0.5)
			local label = Helpers.Visible(host)[1]
			expect(label.Position.X.Offset).to.be.near(0, 1e-6)
			expect(label.Position.Y.Offset).to.be.near(-50, 1e-6)
		end)

		it("lands on the same frame whether it jumps or steps there", function()
			local spread = { SpreadAngle = Vector2.new(180, 180), Speed = NumberRange.new(40, 120) }
			local jumped = Make(spread)
			local stepped = Make(spread, nil, OtherHost())
			Seeded(jumped, 99)
			Seeded(stepped, 99)

			jumped:Emit(20)
			jumped:Pause()
			jumped:SetTime(0.6)

			stepped:Emit(20)
			stepped:Pause()
			for _ = 1, 3 do
				stepped:Forward(0.2)
			end

			local a, b = Helpers.Picture(host), Helpers.Picture(stepped.Emitter.Parent)
			expect(#a).to.equal(20)
			expect(Helpers.Same(a, b)).to.equal(true)
		end)

		it("rewinds to exactly what it showed on the way forward", function()
			local spread = { SpreadAngle = Vector2.new(180, 180) }
			local rewound = Make(spread)
			local direct = Make(spread, nil, OtherHost())
			Seeded(rewound, 5)
			Seeded(direct, 5)

			rewound:Emit(15)
			rewound:Pause()
			rewound:SetTime(0.8)
			rewound:SetTime(0.3)

			direct:Emit(15)
			direct:Pause()
			direct:SetTime(0.3)

			expect(Helpers.Same(Helpers.Picture(host), Helpers.Picture(direct.Emitter.Parent))).to.equal(true)
		end)

		it("never goes below zero", function()
			local effect = Make()
			effect:Emit(1)
			effect:Pause()
			effect:SetTime(0.3)
			effect:Forward(-5)
			expect(Helpers.Visible(host)[1].Position.Y.Offset).to.be.near(0, 1e-6)
		end)

		-- A burst stays in the search window until its longest possible lifetime is up, and a
		-- particle that died before that used to be derived again on every frame.
		it("doesn't derive a particle again once it's dead", function()
			local Simulation = require(Helpers.Package.Simulation)
			local effect = Make({ Lifetime = NumberRange.new(0.1, 1) })
			effect:Emit(20)
			effect:Pause()
			effect:SetTime(0.5)

			local derive = Simulation.Derive
			local calls = 0
			Simulation.Derive = function(...)
				calls += 1
				return derive(...)
			end
			effect:SetTime(0.6)
			effect:SetTime(0.7)
			Simulation.Derive = derive

			expect(calls).to.equal(0)
		end)

		it("clears particles once their lifetime is over", function()
			local effect = Make()
			effect:Emit(10)
			effect:Pause()
			effect:SetTime(1.01)
			expect(Count()).to.equal(0)
		end)

		it("runs at the emitter's TimeScale", function()
			local effect = Make({ TimeScale = 0.5 })
			effect:Emit(1)
			effect:Pause()
			effect:Advance(0.5)
			expect(Helpers.Visible(host)[1].Position.Y.Offset).to.be.near(-25, 1e-6)
		end)
	end)

	describe("randomness", function()
		local spread = { SpreadAngle = Vector2.new(180, 180), Speed = NumberRange.new(40, 120) }

		local function Shot(Effect: any, Host: Frame): { string }
			Effect:Emit(20)
			Effect:Pause()
			Effect:SetTime(0.5)
			return Helpers.Picture(Host)
		end

		it("repeats itself exactly with the same seed", function()
			local a, b = Make(spread), Make(spread, nil, OtherHost())
			Seeded(a, 42)
			Seeded(b, 42)
			expect(Helpers.Same(Shot(a, host), Shot(b, b.Emitter.Parent))).to.equal(true)
		end)

		it("differs with a different seed", function()
			local a, b = Make(spread), Make(spread, nil, OtherHost())
			Seeded(a, 42)
			Seeded(b, 43)
			expect(Helpers.Same(Shot(a, host), Shot(b, b.Emitter.Parent))).to.equal(false)
		end)

		it("rolls a new seed for every run by default", function()
			local effect = Make(spread)
			local first = Shot(effect, host)
			local second = Shot(effect, host)
			expect(Helpers.Same(first, second)).to.equal(false)
		end)
	end)

	describe("steady stream", function()
		it("keeps Rate x Lifetime particles alive", function()
			local effect = Make({ Enabled = true, Rate = 10 })
			effect:SetTime(0.55)
			expect(Count()).to.equal(6) -- born at 0, 0.1 ... 0.5
			effect:SetTime(3.05)
			expect(Count()).to.equal(10) -- born at 2.1 ... 3.0
		end)

		it("emits nothing while disabled", function()
			local effect = Make({ Enabled = false, Rate = 10 })
			effect:SetTime(2)
			expect(Count()).to.equal(0)
		end)

		it("never outgrows the pool", function()
			local effect = Make({ Enabled = true, Rate = 100 }, { SprayMaxParticles = 5 })
			effect:SetTime(3)
			expect(Count() <= 5).to.equal(true)
		end)
	end)

	describe("drawing", function()
		it("layers particles at SprayZIndex plus ZOffset", function()
			local effect = Make({ ZOffset = 2 }, { SprayZIndex = 5 })
			effect:Emit(1)
			effect:Pause()
			expect(Helpers.Visible(host)[1].ZIndex).to.equal(7)
		end)

		it("draws halo layers only for light-emitting particles", function()
			local lit = Make({ LightEmission = 1 }, { SprayGlowLayers = 3 })
			lit:Emit(4)
			lit:Pause()
			expect(Count()).to.equal(12)

			local otherHost = OtherHost()
			local unlit = Make({ LightEmission = 0 }, { SprayGlowLayers = 3 }, otherHost)
			unlit:Emit(4)
			unlit:Pause()
			expect(Count(otherHost)).to.equal(4)
		end)

		it("pushes over-bright colour toward white", function()
			local effect = Make({ Brightness = 2, Color = ColorSequence.new(Color3.new(1, 0, 0)) })
			effect:Emit(1)
			effect:Pause()
			local color = Helpers.Visible(host)[1].ImageColor3
			expect(color.R).to.be.near(1, 1e-3)
			expect(color.G).to.be.near(0.5, 1e-3)
			expect(color.B).to.be.near(0.5, 1e-3)
		end)

		it("waits for its host to be in the DataModel before drawing", function()
			local effect = Make()
			local home = gui.Parent
			gui.Parent = nil
			effect:Emit(3)
			effect:Pause()
			expect(Count()).to.equal(0)

			gui.Parent = home
			effect:SetTime(0)
			expect(Count()).to.equal(3)
		end)
	end)

	describe("Prewarm", function()
		local function Labels(Host: Frame?): number
			local count = 0
			for _, node in (Host or host):GetDescendants() do
				if node:IsA("ImageLabel") then
					count += 1
				end
			end
			return count
		end

		it("builds hidden ImageLabels up front", function()
			local effect = Make()
			effect:Prewarm(10)
			expect(Labels()).to.equal(10)
			expect(Count()).to.equal(0)
		end)

		it("reuses them instead of creating more", function()
			local effect = Make()
			effect:Prewarm(10)
			effect:Emit(6)
			effect:Pause()
			expect(Count()).to.equal(6)
			expect(Labels()).to.equal(10)
		end)

		it("never builds past SprayMaxParticles", function()
			local effect = Make(nil, { SprayMaxParticles = 5 })
			effect:Prewarm(50)
			expect(Labels()).to.equal(5)
		end)

		it("fills the whole pool when no count is given", function()
			local effect = Make(nil, { SprayMaxParticles = 7 })
			effect:Prewarm()
			expect(Labels()).to.equal(7)
		end)

		it("reads SprayPrewarm when the Spray is built", function()
			Make(nil, { SprayPrewarm = 8 })
			expect(Labels()).to.equal(8)
		end)
	end)

	describe("Cleanup", function()
		it("drops the pool", function()
			local effect = Make()
			effect:Emit(3)
			effect:Cleanup()
			expect(host:FindFirstChild("Spray_Probe")).never.to.be.ok()
			expect(Count()).to.equal(0)
		end)

		it("picks up property edits on the next use", function()
			local effect, emitter = Make()
			effect:Emit(1)
			effect:Pause()

			emitter.Size = NumberSequence.new(30)
			effect:SetTime(0.1)
			expect(Helpers.Visible(host)[1].Size.X.Offset).to.be.near(10, 1e-6)

			effect:Cleanup()
			effect:Emit(1)
			effect:Pause()
			expect(Helpers.Visible(host)[1].Size.X.Offset).to.be.near(30, 1e-6)
		end)
	end)

	describe("Destroy", function()
		it("removes the pool and refuses further use", function()
			local effect = Make()
			effect:Emit(3)
			effect:Destroy()
			expect(host:FindFirstChild("Spray_Probe")).never.to.be.ok()
			expect(tostring(effect)).to.equal("Spray [destroyed]")
			expect(function()
				effect:Emit(1)
			end).to.throw()
		end)
	end)
end

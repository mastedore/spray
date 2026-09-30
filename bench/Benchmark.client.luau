-->> Benchmark.client.luau
--> Spray against Emitter2D, with the same burst effect built in both and measured three ways:
-->
-->   steady  N particles alive across 10 emitters, and each library's per-frame update timed
-->           on its own. Nothing spawns or dies while it's measured, so this is the plain
-->           cost of keeping an effect on screen.
-->   burst   how long it takes to get a 200-particle burst on screen, cold (no ImageLabels
-->           exist yet) and warm (reusing the ones from the previous burst). Spray also
-->           runs it on a pool built beforehand with :Prewarm(), which Emitter2D has no
-->           equivalent for.
-->   live    both libraries running on their own schedulers and re-bursting on a timer,
-->           with frame times recorded. This is the closest to a real game, and also the
-->           noisiest, so the two take turns LIVE_ROUNDS times each and each reports its
-->           median round.
-->
--> The steady test also runs a SIMPLE version of the effect, with one flat colour and no
--> spin, which is closer to what most UI effects look like and changes fewer properties
--> per frame.
-->
--> The two effects are matched by hand: same texture, spread, speed, size and transparency
--> curves, colour gradient, rotation, gravity and drag, and the same size on screen. Spray
--> measures in host heights (one stud = 100 px here) and Emitter2D in pixels times host
--> height / 150, which is where the factor of 1.5 between their numbers comes from.
-->
--> It needs a place with Spray at ReplicatedStorage.Packages.Spray and Emitter2D's client
--> under StarterPlayerScripts. Parent this LocalScript under PlayerGui in a playtest (or put
--> it in StarterPlayerScripts) and read the output. It takes about four minutes.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local emitter2DModule = player:WaitForChild("PlayerScripts"):WaitForChild("Emitter2D"):WaitForChild("Emitter2D")

local Spray = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Spray"))
local Emitter2D = require(emitter2DModule)

const HOSTS = 10
const HOST_SIZE = 100
const STEP = 1 / 60

const WARMUP_FRAMES = 15
const SAMPLE_FRAMES = 120
const STEADY_COUNTS = { 100, 250, 500, 1000, 2000, 4000 }
const SIMPLE_COUNTS = { 1000, 4000 }

const BURST_SIZE = 200
const BURST_ROUNDS = 5

--- Particles per emitter per burst in the live test. With 10 emitters bursting every
--- LIVE_INTERVAL and a lifetime of 1 to 1.6 s, that's about 1000 and 4000 alive.
const LIVE_LOADS = { 20, 80 }
const LIVE_INTERVAL = 0.25
const LIVE_WARMUP = 2
const LIVE_SECONDS = 6
const LIVE_ROUNDS = 3

const TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
const COLOR = ColorSequence.new(Color3.fromRGB(255, 190, 60), Color3.fromRGB(255, 60, 30))
const FLAT_COLOR = ColorSequence.new(Color3.fromRGB(255, 190, 60))
const TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.7, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

-- -- Effects -------------------------------------------------------------------

--- Spray's version. Speed 2 to 4 studs/s is 200 to 400 px/s on a 100 px host. `Simple`
--- makes the colour flat and stops the spin.
local function SprayEmitter(Host: Frame, Lifetime: NumberRange, Simple: boolean?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Bench"
	emitter.Enabled = false
	emitter.Texture = TEXTURE
	emitter.Color = if Simple then FLAT_COLOR else COLOR
	emitter.Transparency = TRANSPARENCY
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.3, 0.25, 0.05),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = Lifetime
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -3, 0)
	emitter.Drag = 1
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = if Simple then NumberRange.new(0) else NumberRange.new(-180, 180)
	emitter.LightEmission = 0
	emitter.LightInfluence = 0
	emitter:SetAttribute("SprayMaxParticles", 1000)
	emitter.Parent = Host
	return emitter
end

--- Emitter2D's version, cloned from its own template so every attribute it checks for is
--- there. Size 37.5 is 25 px on a 100 px host (Spray's 0.25 studs) and Speed 300 to 600 is
--- 200 to 400 px/s.
local function Emitter2DConfig(Host: Frame, Lifetime: NumberRange, Paused: boolean, Simple: boolean?): Configuration
	local config = emitter2DModule.Emitter:Clone()
	for _, tag in config:GetTags() do
		config:RemoveTag(tag)
	end
	config.Name = "Bench"

	local attributes = {
		Enabled = false,
		Paused = Paused,
		Texture = TEXTURE,
		Color = if Simple then FLAT_COLOR else COLOR,
		Transparency = TRANSPARENCY,
		Size = NumberRange.new(37.5),
		Scale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.3, 1, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Squash = NumberSequence.new(0.5),
		LifeTime = Lifetime,
		Speed = NumberRange.new(300, 600),
		SpreadAngle = 180,
		EmissionDirection = 0,
		EmissionShape = "Point",
		EmissionDirectionMode = "FromUp",
		Acceleration = Vector2.new(0, 450),
		Drag = 1,
		Rotation = NumberRange.new(0, 360),
		RotationSpeed = if Simple then NumberRange.new(0) else NumberRange.new(-180, 180),
		Orientation = "Normal",
		FlipbookLayout = "None",
		SizeConstraint = "RelativeYY",
		UseScreenSize = false,
		MasterScale = 1,
		Depth = NumberRange.new(0),
		IgnoreClipsDescendants = true,
		IgnoreGraphicsLevel = true,
	}
	for name, value in attributes do
		config:SetAttribute(name, value)
	end

	config.Parent = Host
	return config
end

--- What Emitter2D's CollectionService loader does for a tagged config.
local function StartEmitter2D(Config: Configuration): any
	local entity = Emitter2D.new()
	entity:Initiate(Config)
	return entity
end

-- -- Helpers -------------------------------------------------------------------

--- A ScreenGui with 10 empty 100x100 hosts in two rows across the middle of the screen.
local function Stage(): (ScreenGui, { Frame })
	local gui = Instance.new("ScreenGui")
	gui.Name = "SprayBenchmark"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local hosts = {}
	for index = 1, HOSTS do
		local column, row = (index - 1) % 5, (index - 1) // 5
		local host = Instance.new("Frame")
		host.Name = `Host{index}`
		host.BackgroundTransparency = 1
		host.AnchorPoint = Vector2.new(0.5, 0.5)
		host.Size = UDim2.fromOffset(HOST_SIZE, HOST_SIZE)
		host.Position = UDim2.new(0.5, (column - 2) * 180, 0.5, (row - 1) * 200)
		host.Parent = gui
		hosts[index] = host
	end

	gui.Parent = playerGui
	return gui, hosts
end

local function CountVisible(Root: Instance): number
	local count = 0
	for _, node in Root:GetDescendants() do
		if node:IsA("ImageLabel") and node.Visible and node.ImageTransparency < 1 then
			count += 1
		end
	end
	return count
end

local function Sorted(Values: { number }): { number }
	local copy = table.clone(Values)
	table.sort(copy)
	return copy
end

local function Median(Values: { number }): number
	local sorted = Sorted(Values)
	local middle = #sorted // 2
	if #sorted % 2 == 0 then
		return (sorted[middle] + sorted[middle + 1]) / 2
	end
	return sorted[middle + 1]
end

local function Percentile(Values: { number }, Fraction: number): number
	local sorted = Sorted(Values)
	return sorted[math.clamp(math.ceil(#sorted * Fraction), 1, #sorted)]
end

local function Mean(Values: { number }): number
	local total = 0
	for _, value in Values do
		total += value
	end
	return total / #Values
end

local function Settle()
	for _ = 1, 30 do
		RunService.RenderStepped:Wait()
	end
end

--- Runs `Step` once per rendered frame, a few times to warm up and then SAMPLE_FRAMES
--- times with a timer around it. Returns the time of each measured call, in seconds.
local function Sample(Step: () -> ()): { number }
	for _ = 1, WARMUP_FRAMES do
		RunService.RenderStepped:Wait()
		Step()
	end
	local times = table.create(SAMPLE_FRAMES)
	for index = 1, SAMPLE_FRAMES do
		RunService.RenderStepped:Wait()
		local started = os.clock()
		Step()
		times[index] = os.clock() - started
	end
	return times
end

-- -- Steady --------------------------------------------------------------------

local function SteadySpray(Total: number, Simple: boolean?): ({ number }, number)
	local gui, hosts = Stage()
	local effects = {}
	for index, host in hosts do
		local effect = Spray.New(SprayEmitter(host, NumberRange.new(10), Simple))
		effect:UseRandom(false)
		effect:RandomSeed(index)
		effect:Emit(Total // HOSTS)
		-- Paused takes it off Spray's scheduler, so the timed loop below is the only thing
		-- moving it. The loop does exactly what the scheduler would.
		effect:Pause()
		effects[index] = effect
	end

	local times = Sample(function()
		for _, effect in effects do
			effect:Advance(STEP)
		end
	end)

	local drawn = CountVisible(gui)
	for _, effect in effects do
		effect:Destroy()
	end
	gui:Destroy()
	return times, drawn
end

local function SteadyEmitter2D(Total: number, Simple: boolean?): ({ number }, number)
	local gui, hosts = Stage()
	local entities = {}
	for index, host in hosts do
		-- Paused keeps Emitter2D's own RenderStep loop from stepping it. The timed loop
		-- below does the same per-emitter work that loop does.
		local entity = StartEmitter2D(Emitter2DConfig(host, NumberRange.new(10), true, Simple))
		for _ = 1, Total // HOSTS do
			entity:SpawnParticle()
		end
		entities[index] = entity
	end

	local times = Sample(function()
		for _, entity in entities do
			local config = entity.Config
			entity.ParticleFolder.Parent = config.Parent
			local _ = config:GetAttribute("Paused")
			task.spawn(entity.Update, entity, STEP)
		end
	end)

	local drawn = CountVisible(gui)
	for _, entity in entities do
		entity:Destroy()
	end
	gui:Destroy()
	return times, drawn
end

-- -- Burst ---------------------------------------------------------------------

--- Cold is the first burst of a new emitter, warm is a second one right after that reuses
--- the first one's ImageLabels. Spray's warm time also includes hiding the previous burst,
--- which Emitter2D gets for free here because its clear isn't timed.
local function BurstSpray(): ({ number }, { number }, { number })
	local cold, warm, prewarmed = {}, {}, {}
	for round = 1, BURST_ROUNDS do
		local gui, hosts = Stage()
		local effect = Spray.New(SprayEmitter(hosts[1], NumberRange.new(1, 1.6)))
		RunService.RenderStepped:Wait()

		local started = os.clock()
		effect:Emit(BURST_SIZE)
		cold[round] = os.clock() - started

		effect:Pause()
		RunService.RenderStepped:Wait()

		started = os.clock()
		effect:Emit(BURST_SIZE)
		warm[round] = os.clock() - started

		-- A first burst again, on a Spray whose pool was built ahead of time.
		local ready = Spray.New(SprayEmitter(hosts[2], NumberRange.new(1, 1.6)))
		ready:Prewarm(BURST_SIZE)
		RunService.RenderStepped:Wait()

		started = os.clock()
		ready:Emit(BURST_SIZE)
		prewarmed[round] = os.clock() - started

		effect:Destroy()
		ready:Destroy()
		gui:Destroy()
		RunService.RenderStepped:Wait()
	end
	return cold, warm, prewarmed
end

--- Spawning plus one Update, since Spray's :Emit() also draws the burst in the same call.
local function BurstEmitter2D(): ({ number }, { number })
	local cold, warm = {}, {}
	for round = 1, BURST_ROUNDS do
		local gui, hosts = Stage()
		local entity = StartEmitter2D(Emitter2DConfig(hosts[1], NumberRange.new(1, 1.6), true))
		RunService.RenderStepped:Wait()

		local started = os.clock()
		for _ = 1, BURST_SIZE do
			entity:SpawnParticle()
		end
		entity:Update(STEP)
		cold[round] = os.clock() - started

		entity:ClearAllParticles()
		RunService.RenderStepped:Wait()

		started = os.clock()
		for _ = 1, BURST_SIZE do
			entity:SpawnParticle()
		end
		entity:Update(STEP)
		warm[round] = os.clock() - started

		entity:Destroy()
		gui:Destroy()
		RunService.RenderStepped:Wait()
	end
	return cold, warm
end

-- -- Live ----------------------------------------------------------------------

type LiveResult = {
	Frames: { number },
	Busy: number,
	Alive: number,
}

--- Calls `Burst` every LIVE_INTERVAL while the library runs on its own. Records every frame
--- time after the warmup, how long the library spent working in that stretch (its own
--- update, through `Busy`, plus the bursts) and how many particles were alive on average.
--- The count is sampled every few frames because a single reading depends on whether a
--- burst just went off.
local function Live(Burst: () -> (), Busy: () -> number, ResetBusy: () -> (), Alive: () -> number): LiveResult
	local frames = {}
	local alive = {}
	local burstBusy = 0
	local elapsed = 0
	local sinceBurst = LIVE_INTERVAL
	local measuring = false
	local last = os.clock()

	while elapsed < LIVE_WARMUP + LIVE_SECONDS do
		local delta = RunService.Heartbeat:Wait()
		local now = os.clock()
		local frame = now - last
		last = now
		elapsed += delta

		if measuring then
			table.insert(frames, frame)
			if #frames % 10 == 0 then
				table.insert(alive, Alive())
			end
		elseif elapsed >= LIVE_WARMUP then
			measuring = true
			burstBusy = 0
			ResetBusy()
		end

		sinceBurst += delta
		if sinceBurst >= LIVE_INTERVAL then
			sinceBurst -= LIVE_INTERVAL
			local started = os.clock()
			Burst()
			burstBusy += os.clock() - started
		end
	end

	return {
		Frames = frames,
		Busy = Busy() + burstBusy,
		Alive = if #alive > 0 then Mean(alive) else 0,
	}
end

local function LiveBaseline(): LiveResult
	return Live(function() end, function() return 0 end, function() end, function() return 0 end)
end

local function LiveSpray(PerBurst: number): LiveResult
	local gui, hosts = Stage()
	local busy = 0
	local effects = {}
	for index, host in hosts do
		local effect = Spray.New(SprayEmitter(host, NumberRange.new(1, 1.6))) :: any
		-- Spray's scheduler calls member:Advance(dt), so an Advance on the object itself
		-- is what it runs.
		effect.Advance = function(self, Delta: number)
			local started = os.clock()
			Spray.Advance(self, Delta)
			busy += os.clock() - started
		end
		effects[index] = effect
	end

	local result = Live(function()
		for _, effect in effects do
			effect:Emit(PerBurst)
		end
	end, function()
		return busy
	end, function()
		busy = 0
	end, function()
		local count = 0
		for _, effect in effects do
			for _ in effect._renderer.Active do
				count += 1
			end
		end
		return count
	end)

	for _, effect in effects do
		effect:Destroy()
	end
	gui:Destroy()
	return result
end

local function LiveEmitter2D(PerBurst: number): LiveResult
	local gui, hosts = Stage()
	local busy = 0
	local entities = {}
	for index, host in hosts do
		local entity = StartEmitter2D(Emitter2DConfig(host, NumberRange.new(1, 1.6), false))
		-- Emitter2D's loop runs task.spawn(Entity.Update, Entity, dt), which picks this up.
		entity.Update = function(self, Delta: number)
			local started = os.clock()
			Emitter2D.Update(self, Delta)
			busy += os.clock() - started
		end
		entities[index] = entity
	end

	local result = Live(function()
		for _, entity in entities do
			for _ = 1, PerBurst do
				entity:SpawnParticle()
			end
		end
	end, function()
		return busy
	end, function()
		busy = 0
	end, function()
		local count = 0
		for _, entity in entities do
			count += entity.ParticleCount
		end
		return count
	end)

	for _, entity in entities do
		entity:Destroy()
	end
	gui:Destroy()
	return result
end

-- -- Run -----------------------------------------------------------------------

local function Milliseconds(Seconds: number): number
	return Seconds * 1000
end

local report = {
	Steady = {},
	Burst = {},
	Live = {},
}

print("[bench] started: steady, burst, live. About four minutes.")
Settle()

-- Each count runs A B B A and keeps the better median of the two, so neither library
-- always goes first.
local function Steady(Total: number, Simple: boolean)
	local sprayA, sprayDrawn = SteadySpray(Total, Simple)
	Settle()
	local e2dA, e2dDrawn = SteadyEmitter2D(Total, Simple)
	Settle()
	local e2dB = SteadyEmitter2D(Total, Simple)
	Settle()
	local sprayB = SteadySpray(Total, Simple)
	Settle()

	local spray = math.min(Median(sprayA), Median(sprayB))
	local e2d = math.min(Median(e2dA), Median(e2dB))

	table.insert(report.Steady, {
		Particles = Total,
		Simple = Simple,
		SprayMs = Milliseconds(spray),
		SprayDrawn = sprayDrawn,
		Emitter2DMs = Milliseconds(e2d),
		Emitter2DDrawn = e2dDrawn,
	})
	print(string.format(
		"[bench] steady %-6s %4d particles | Spray %7.3f ms (%4d drawn) | Emitter2D %7.3f ms (%4d drawn) | Emitter2D/Spray x%.2f",
		if Simple then "simple" else "full", Total, Milliseconds(spray), sprayDrawn, Milliseconds(e2d), e2dDrawn, e2d / spray
	))
end

for _, total in STEADY_COUNTS do
	Steady(total, false)
end
for _, total in SIMPLE_COUNTS do
	Steady(total, true)
end

do
	local sprayCold, sprayWarm, sprayPrewarmed = BurstSpray()
	Settle()
	local e2dCold, e2dWarm = BurstEmitter2D()
	Settle()

	report.Burst = {
		Size = BURST_SIZE,
		SprayColdMs = Milliseconds(Median(sprayCold)),
		SprayWarmMs = Milliseconds(Median(sprayWarm)),
		SprayPrewarmedMs = Milliseconds(Median(sprayPrewarmed)),
		Emitter2DColdMs = Milliseconds(Median(e2dCold)),
		Emitter2DWarmMs = Milliseconds(Median(e2dWarm)),
	}
	print(string.format(
		"[bench] burst of %d | cold: Spray %.3f ms, Emitter2D %.3f ms | warm: Spray %.3f ms, Emitter2D %.3f ms | prewarmed: Spray %.3f ms",
		BURST_SIZE, report.Burst.SprayColdMs, report.Burst.Emitter2DColdMs, report.Burst.SprayWarmMs, report.Burst.Emitter2DWarmMs,
		report.Burst.SprayPrewarmedMs
	))
end

local function Summarise(Name: string, Load: number, Result: LiveResult)
	local frames = Result.Frames
	local entry = {
		Library = Name,
		PerBurst = Load,
		Alive = math.round(Result.Alive),
		Fps = 1 / Mean(frames),
		FrameMeanMs = Milliseconds(Mean(frames)),
		FrameP95Ms = Milliseconds(Percentile(frames, 0.95)),
		FrameMaxMs = Milliseconds(Percentile(frames, 1)),
		LibraryMsPerFrame = Milliseconds(Result.Busy / #frames),
	}
	table.insert(report.Live, entry)
	print(string.format(
		"[bench] live %-9s load %2d | %4d alive | %5.1f fps | frame mean %6.2f ms, p95 %6.2f ms, max %6.2f ms | library %6.3f ms/frame",
		Name, Load, entry.Alive, entry.Fps, entry.FrameMeanMs, entry.FrameP95Ms, entry.FrameMaxMs, entry.LibraryMsPerFrame
	))
end

local function LibraryMs(Result: LiveResult): number
	return Result.Busy / #Result.Frames
end

-- The same live run can swing by 2x from one minute to the next on a laptop, so the two
-- libraries take turns and who goes first alternates. Each one then reports its median
-- round, whole, so every number on the line comes from the same round.
Summarise("Baseline", 0, LiveBaseline())
Settle()
for _, load in LIVE_LOADS do
	local rounds: { [string]: { LiveResult } } = { Spray = {}, Emitter2D = {} }
	for round = 1, LIVE_ROUNDS do
		local order = if round % 2 == 1 then { "Spray", "Emitter2D" } else { "Emitter2D", "Spray" }
		for _, name in order do
			local result = if name == "Spray" then LiveSpray(load) else LiveEmitter2D(load)
			table.insert(rounds[name], result)
			print(string.format("[bench] live round %d %-9s load %2d | library %6.3f ms/frame", round, name, load, Milliseconds(LibraryMs(result))))
			Settle()
		end
	end
	for _, name in { "Spray", "Emitter2D" } do
		local results = rounds[name]
		table.sort(results, function(A, B)
			return LibraryMs(A) < LibraryMs(B)
		end)
		Summarise(name, load, results[(#results + 1) // 2])
	end
end

print("[bench-json] " .. HttpService:JSONEncode(report))
print("[bench] done")

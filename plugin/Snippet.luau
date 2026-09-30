--!strict
-->> Snippet.luau
--> Writes the Luau that plays exported origins with Spray, set up the way they were in the
--> playground: the seed, every burst of the run on screen at the exact time it went off,
--> the loop and its length, and a frozen frame when the origin was paused mid-run.
-->
--> BURSTS ON THE TIMELINE. Spray keeps bursts as data on its timeline, so a burst doesn't
--> have to be fired at the moment it should go off. Moving the clock to that time,
--> emitting, and moving it back queues it there, and it goes off when the clock reaches it
--> again. That's frame exact and follows TimeScale for free, which task.delay would do
--> neither of. It's also how the playground itself replays a run after every edit.

local Origin = require(script.Parent.playground.Origin)

type Origin = Origin.Origin

--- One exported origin, and the names its emitter ended up under in the export.
export type Layer = {
	Origin: Origin,
	Frame: string,
	Emitter: string,
}

const KEYWORDS: { [string]: boolean } = {
	["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true, ["else"] = true,
	["elseif"] = true, ["end"] = true, ["export"] = true, ["false"] = true, ["for"] = true,
	["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true,
	["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true,
	["true"] = true, ["type"] = true, ["typeof"] = true, ["until"] = true, ["while"] = true,
	["const"] = true,
	-- Names the generated script uses itself, or that would shadow a global it needs.
	["game"] = true, ["script"] = true, ["gui"] = true, ["task"] = true, ["Spray"] = true,
	["ReplicatedStorage"] = true, ["Loop"] = true,
}

const RULE_WIDTH = 88

local Snippet = {}

-- -- Names ---------------------------------------------------------------------

--- "Sparkle Burst 2" -> "SparkleBurst2". Always a valid identifier, so it can be used both
--- as an Instance name and after a dot in the generated code.
function Snippet.PascalCase(Name: string): string
	local words = {}
	for word in string.gmatch(Name, "%w+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	local joined = table.concat(words)
	if joined == "" then
		return "VFX"
	end
	if string.match(joined, "^%d") then
		joined = "VFX" .. joined
	end
	return joined
end

local function CamelCase(Name: string): string
	local pascal = Snippet.PascalCase(Name)
	local camel = string.lower(string.sub(pascal, 1, 1)) .. string.sub(pascal, 2)
	if KEYWORDS[camel] then
		camel ..= "VFX"
	end
	return camel
end

local function Unique(Taken: { [string]: boolean }, Base: string): string
	local name = Base
	local index = 2
	while Taken[name] do
		name = `{Base}{index}`
		index += 1
	end
	Taken[name] = true
	return name
end

-- -- Formatting ----------------------------------------------------------------

local function Number(Value: number): string
	local text = string.format("%.3f", Value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return if text == "-0" then "0" else text
end

local function Rule(Title: string): string
	local head = `-- -- {Title} `
	return head .. string.rep("-", math.max(4, RULE_WIDTH - #head))
end

-- -- Generation ----------------------------------------------------------------

type Plan = {
	Variable: string,
	Run: string,
	Layer: Layer,
}

--- How the playback section should start one layer. Mirrors what the origin was doing.
local function Playback(Plan: Plan, Lines: { string })
	local origin = Plan.Layer.Origin
	local emitter = origin.Emitter
	local duration = origin:GetDuration()
	local clock = origin:Clock()
	local timeScale = emitter.TimeScale

	-- Paused partway through: hold that exact frame.
	if not origin.Playing and clock > 1e-3 and clock < duration - 1e-3 then
		table.insert(Lines, `-- {origin.Name} was paused at {Number(clock)} s, so this holds that frame.`)
		table.insert(Lines, `-- Leave only {Plan.Run}() to have it play instead.`)
		table.insert(Lines, `{Plan.Run}()`)
		table.insert(Lines, `{Plan.Variable}:SetTime({Number(clock)})`)
		table.insert(Lines, `{Plan.Variable}:Pause()`)
		return
	end

	if not origin.Loop then
		table.insert(Lines, `{Plan.Run}() -- Loop was off: one run`)
		return
	end

	if timeScale <= 0 then
		table.insert(Lines, `{Plan.Run}() -- TimeScale is 0, so it never moves: one run is all it takes`)
		return
	end

	-- A plain stream on an automatic length only restarted in the playground so you could
	-- watch it build up. Left alone it just keeps flowing, which is what you'd want.
	local stream = emitter.Enabled and emitter.Rate > 0
	if stream and origin.Duration == nil and #origin.Bursts == 0 then
		table.insert(Lines, `{Plan.Run}() -- a stream keeps flowing by itself, no loop needed`)
		return
	end

	local seconds = duration / timeScale
	local note = if timeScale ~= 1
		then ` -- {Number(duration)} s of effect time at TimeScale {Number(timeScale)}`
		else ""
	table.insert(Lines, `Loop({Plan.Run}, {Number(seconds)}){note}`)
end

--- The Luau for a LocalScript sitting in the exported ScreenGui, next to its frames.
function Snippet.Generate(Layers: { Layer }): string
	local lines: { string } = {}
	local function Line(Text: string?)
		table.insert(lines, Text or "")
	end

	local taken: { [string]: boolean } = table.clone(KEYWORDS)
	local plans: { Plan } = {}
	for _, layer in Layers do
		local variable = Unique(taken, CamelCase(layer.Origin.Name))
		local run = Unique(taken, "Play" .. Snippet.PascalCase(layer.Origin.Name))
		table.insert(plans, { Variable = variable, Run = run, Layer = layer })
	end

	Line("-->> PlayVFX")
	Line("--> Plays the effect exported from the Spray playground, set up the way it was there.")
	Line("--> Written by the Spray plugin: copy whatever you need into your own code. It needs")
	Line("--> Spray at ReplicatedStorage.Packages.Spray, which the plugin's Import button puts there.")
	Line()
	Line('local ReplicatedStorage = game:GetService("ReplicatedStorage")')
	Line()
	Line("local Spray = require(ReplicatedStorage.Packages.Spray)")
	Line()
	Line("local gui = script.Parent")

	for index, plan in plans do
		local layer = plan.Layer
		local origin = layer.Origin
		local variable = plan.Variable
		local seed = tostring(origin.Seed)

		Line()
		Line(Rule(origin.Name))
		Line()
		Line(`local {variable} = Spray.New(gui.{layer.Frame}.{layer.Emitter})`)
		if origin.RandomEachRun then
			Line(`-- A new seed every run, like a real emitter. The run on screen when you exported`)
			Line(`-- was seed {seed}; these two lines would play exactly that one every time:`)
			Line(`-- {variable}:UseRandom(false)`)
			Line(`-- {variable}:RandomSeed({seed})`)
		else
			Line(`-- A fixed seed, so every run is the same particles.`)
			Line(`{variable}:UseRandom(false)`)
			Line(`{variable}:RandomSeed({seed})`)
		end
		Line()

		if index == 1 then
			Line(`--- One run of {origin.Name} from the start. A paused Spray rewinds to zero when`)
			Line("--- emitted into, so pausing first makes every call start over instead of stacking")
			Line("--- on top of the previous run.")
		else
			Line(`--- One run of {origin.Name} from the start.`)
		end
		Line(`local function {plan.Run}()`)
		Line(`	{variable}:Pause()`)

		-- Replayed in the order they were fired, which is what their random streams follow.
		-- That isn't always time order (emitting after scrubbing back), so the clock is moved
		-- before any burst it isn't already sitting on.
		local bursts = origin.Bursts
		if #bursts == 0 or bursts[1].Time > 0 then
			-- Emitting nothing still does the rewind, and starts the stream if it has one.
			Line(`	{variable}:Emit(0)`)
		end
		local at = 0
		local explained = false
		for _, burst in bursts do
			if burst.Time ~= at then
				if not explained then
					explained = true
					Line("	-- The bursts fired later in the run, queued on its timeline: the clock goes")
					Line("	-- there, emits, and comes back. Each goes off when the clock reaches it.")
				end
				at = burst.Time
				Line(`	{variable}:SetTime({Number(at)})`)
			end
			Line(`	{variable}:Emit({burst.Count})`)
		end
		if at ~= 0 then
			Line(`	{variable}:SetTime(0)`)
		end
		Line("end")
	end

	-- Playback. The Loop helper only goes in when something actually loops.
	local playback: { string } = {}
	for _, plan in plans do
		Playback(plan, playback)
	end
	local loops = false
	for _, line in playback do
		if string.sub(line, 1, 5) == "Loop(" then
			loops = true
		end
	end

	Line()
	Line(Rule("Playback"))
	Line()
	if loops then
		Line("--- Calls `Run` every `Seconds`, forever.")
		Line("local function Loop(Run: () -> (), Seconds: number)")
		Line("	task.spawn(function()")
		Line("		while true do")
		Line("			Run()")
		Line("			task.wait(Seconds)")
		Line("		end")
		Line("	end)")
		Line("end")
		Line()
	end
	for _, line in playback do
		Line(line)
	end

	return table.concat(lines, "\n") .. "\n"
end

return Snippet

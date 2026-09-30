--!strict
-->> Preview.luau
--> Plays a Spray in Studio WITHOUT running the game, so you can tweak a VFX layer in the
--> Properties panel and see the result right away instead of starting a playtest.
-->
--> You don't need a plugin. RenderStepped fires in Edit mode and StarterGui is drawn on
--> top of the edit viewport, so a Spray built from an emitter in StarterGui just animates.
--> Paste this into the command bar:
-->
-->     require(game.ReplicatedStorage.Packages.Spray.Preview).Play()
-->
--> with a ParticleEmitter (or anything that contains some) selected in Explorer. To stop:
-->
-->     require(game.ReplicatedStorage.Packages.Spray.Preview).Stop()
-->
--> Other calls you might want:
-->
-->     .Play(target, options)  target can be an emitter, a Frame, a whole ScreenGui or
-->                             pretty much anything, and every ParticleEmitter under it
-->                             gets played. options: Count, Interval, Seed, Show.
-->     .Scrub(0.15)            freeze every previewed emitter at one moment. This is the
-->                             one to use when tuning a Size or Transparency curve, since
-->                             the picture stays still while you edit the sequence.
-->     .Step(0.02)             move the frozen moment forward a little. Handy for going
-->                             through a burst frame by frame to find where a curve breaks.
-->     .Stop()                 stop, delete every pool and restore visibility.
-->
--> ALWAYS call .Stop() before saving the place. The pools themselves are never saved (they
--> aren't Archivable), but whatever hidden UI the preview turned on to show them would be.
--> Stop is also extra careful on purpose. Besides destroying the Sprays it knows about, it also
--> looks for pool frames by NAME, because re-requiring this module after an edit loses the
--> table of live previews and those pools would be left behind.
-->
--> This module is a dev tool and isn't part of the effect. Nothing in the package requires
--> it, so it never runs in game.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
-- Copyright (C) 2026 Mastedore.
--
-- The --[=[ ]=] blocks in this file are Moonwave doc comments, which become the API page of
-- the docs site. Keep internal comments on plain -- so Moonwave doesn't try to publish them.

local RunService = game:GetService("RunService")

local Spray = require(script.Parent)

type Spray = Spray.Spray

--[=[
	@class Preview

	Plays emitters in Roblox Studio without starting a playtest, so you can change a property
	and see the result a few seconds later. It's a module inside Spray that nothing else
	requires, so it never runs in your game.

	Select a ParticleEmitter in the Explorer, or a Frame or ScreenGui that has some inside,
	then paste this into Studio's command bar and press Enter:

	```lua
	require(game.ReplicatedStorage.Packages.Spray.Preview).Play()
	```

	The selected emitters play in bursts, over and over, right in the edit viewport. This works
	for UI in StarterGui, because Studio draws StarterGui on top of the viewport while you
	edit. Preview reads the emitters when it starts, so after changing a property, run
	[Preview.Play] again to see it.

	To stop:

	```lua
	require(game.ReplicatedStorage.Packages.Spray.Preview).Stop()
	```

	:::caution Stop before you save
	To make the emitters visible, Preview turns on any hidden UI above them (`Visible` on
	GuiObjects, `Enabled` on ScreenGuis), and [Preview.Stop] turns it back off. If you save
	the place before stopping, that UI is saved turned on.
	:::

	Every function returns a one-line message saying what it did, such as how many emitters
	are playing. Wrap the call in `print()` to see it in the Output window.

	The Spray Studio plugin has a Preview button that does the same job with a playback
	window, and picks up property changes on its own.
]=]

--[=[
	@interface Options
	@within Preview
	.Count number? -- Particles per burst. The default is 30. An emitter with a `BurstCount` number attribute uses that instead.
	.Interval number? -- Seconds between bursts. The default is the longest `Lifetime` Max among the emitters plus 0.45, so each burst ends before the next one starts.
	.Seed number? -- Uses this seed for every burst, so each loop looks the same. Handy for comparing an effect before and after a change.
	.Show boolean? -- Turns on hidden UI above the emitters so you can see them. The default is `true`.

	Settings for [Preview.Play]. Every field is optional, and so is the table itself.

	```lua
	local Preview = require(game.ReplicatedStorage.Packages.Spray.Preview)
	print(Preview.Play(nil, { Count = 50, Seed = 3 }))
	```
]=]
export type Options = {
	Count: number?,     -- particles per burst; a BurstCount attribute on the emitter takes priority
	Interval: number?,  -- seconds between bursts; defaults to the longest lifetime plus a short gap
	Seed: number?,      -- fixes the seed so every loop looks the same, useful for A/B tuning
	Show: boolean?,     -- makes hidden ancestors visible while previewing (default true)
}

-- A short pause between the last particle dying and the next burst, so the loop looks
-- like separate bursts and not like one continuous stream.
const LOOP_GAP = 0.45

local Preview = {}

type Entry = {
	Effect: Spray,
	Count: number,
}

type Restore = {
	Object: Instance,
	Property: string,
	Value: any,
}

local entries: { Entry } = {}
local restores: { Restore } = {}
local connection: RBXScriptConnection? = nil
local interval = 1
local elapsed = 0

-- -- Helpers -------------------------------------------------------------------

-- Every ParticleEmitter at or under `Root`.
local function Collect(Root: Instance): { ParticleEmitter }
	local found: { ParticleEmitter } = {}
	if Root:IsA("ParticleEmitter") then
		table.insert(found, Root)
		return found
	end
	for _, node in Root:GetDescendants() do
		if node:IsA("ParticleEmitter") then
			table.insert(found, node)
		end
	end
	return found
end

-- Makes `Object` visible and saves the old value so Stop can restore it. A preview that
-- leaves half your UI turned on without telling you is worse than no preview at all.
local function Force(Object: Instance, Property: string, Value: any)
	local current = (Object :: any)[Property]
	if current == Value then
		return
	end
	table.insert(restores, { Object = Object, Property = Property, Value = current })
	;(Object :: any)[Property] = Value
end

-- Walks up from an emitter and turns on anything that would keep it off screen.
local function Reveal(Emitter: ParticleEmitter)
	local node: Instance? = Emitter.Parent
	while node do
		if node:IsA("GuiObject") then
			Force(node, "Visible", true)
		elseif node:IsA("LayerCollector") then
			Force(node, "Enabled", true)
			break
		end
		node = node.Parent
	end
end

-- Deletes pool containers by name, as a backup for Spray:Destroy(). Re-requiring this
-- module loses `entries`, and without this the previous preview's ImageLabels would stay
-- in the place forever.
local function Sweep(): number
	local swept = 0
	for _, root in { game:GetService("StarterGui"), game:GetService("Players").LocalPlayer } do
		if not root then
			continue
		end
		for _, node in root:GetDescendants() do
			if node:IsA("Frame") and node.Name:sub(1, 6) == "Spray_" then
				node:Destroy()
				swept += 1
			end
		end
	end
	return swept
end

-- -- API -----------------------------------------------------------------------

--[=[
	Stops the preview and puts the place back the way it was. It destroys every Spray the
	preview made, turns hidden UI back off, and deletes any leftover particle Frames it finds
	in StarterGui.

	The leftovers come from requiring the module again after editing it while a preview was
	running. The new copy doesn't know about the old preview, so `Stop` finds the old Frames
	by name instead (Spray names them `Spray_` plus the emitter's name) and deletes them.

	:::caution
	That search deletes every Frame whose name starts with `Spray_` in StarterGui (and in your
	player, during a playtest), including your own. Don't give your UI names that start that
	way.
	:::

	@return string -- A message that says how many leftover Frames were deleted.
]=]
function Preview.Stop(): string
	if connection then
		connection:Disconnect()
		connection = nil
	end

	for _, entry in entries do
		entry.Effect:Destroy()
	end
	table.clear(entries)

	for index = #restores, 1, -1 do
		local restore = restores[index]
		if restore.Object.Parent then
			(restore.Object :: any)[restore.Property] = restore.Value
		end
	end
	table.clear(restores)

	local swept = Sweep()
	return ("Spray preview stopped (%d stray pool%s cleaned)"):format(swept, if swept == 1 then "" else "s")
end

--[=[
	Starts looping the emitters in `Target`, or in whatever is selected in the Explorer if you
	don't pass anything.

	`Target` can be a ParticleEmitter or anything that contains some: a Frame, a ScreenGui,
	even all of StarterGui. Every emitter inside it plays, all of them bursting at the same
	time. When it uses the selection, only the first selected object counts.

	```lua
	local Preview = require(game.ReplicatedStorage.Packages.Spray.Preview)

	Preview.Play(game.StarterGui.Shop.BuyButton) -- every emitter in the button
	Preview.Play(nil, { Count = 80 }) -- the selection, 80 particles per burst
	```

	Emitters that aren't inside a GuiObject are skipped, and the returned message lists them.
	If a preview is already running, it's stopped first.

	@param Target Instance? -- What to play. Leave it out to use the selection.
	@param Config Options? -- Optional settings. See [Preview.Options].
	@return string -- A message saying how many emitters are playing, or why nothing is.
]=]
function Preview.Play(Target: Instance?, Config: Options?): string
	Preview.Stop()

	local options: Options = Config or {}

	local root = Target
	if not root then
		local selection = game:GetService("Selection"):Get()
		root = selection[1]
	end
	if not root then
		return "Spray preview: nothing to play. Select a ParticleEmitter (or something containing some) in Explorer, or pass one in."
	end

	local emitters = Collect(root)
	if #emitters == 0 then
		return ("Spray preview: no ParticleEmitter found in %s"):format(root:GetFullName())
	end

	local longest = 0
	local skipped = {}

	for _, emitter in emitters do
		-- A Spray draws inside the GuiObject its emitter lives under. One sitting on an
		-- Attachment in the workspace has nowhere to draw, and telling the user here is a
		-- lot more helpful than the assert further down in Spec.
		if not emitter:FindFirstAncestorWhichIsA("GuiObject") then
			table.insert(skipped, emitter.Name)
			continue
		end

		if options.Show ~= false then
			Reveal(emitter)
		end

		local effect = Spray.New(emitter)
		if options.Seed then
			effect:UseRandom(false)
			effect:RandomSeed(options.Seed)
		end

		local authored = emitter:GetAttribute("BurstCount")
		table.insert(entries, {
			Effect = effect,
			Count = if typeof(authored) == "number" and authored > 0
				then authored
				else options.Count or 30,
		})
		longest = math.max(longest, emitter.Lifetime.Max)
	end

	if #entries == 0 then
		return ("Spray preview: none of the %d emitter(s) under %s are inside a GuiObject, so there is nothing to draw into."):format(
			#emitters, root:GetFullName())
	end

	interval = options.Interval or (longest + LOOP_GAP)
	elapsed = interval -- fire the first burst on the next step instead of waiting a full interval

	connection = RunService.Heartbeat:Connect(function(delta: number)
		elapsed += delta
		if elapsed < interval then
			return
		end
		elapsed = 0
		for _, entry in entries do
			entry.Effect:Emit(entry.Count)
		end
	end)

	local note = if #skipped > 0
		then (" (skipped %d not under a GuiObject: %s)"):format(#skipped, table.concat(skipped, ", "))
		else ""
	return ("Spray preview: looping %d emitter(s) every %.2fs%s. Call .Stop() when done."):format(
		#entries, interval, note)
end

--[=[
	Freezes every previewed emitter at `Time` seconds into a burst and stops the loop. The
	picture holds still, which helps when you're looking at a Size or Transparency curve and
	want to see one exact moment of it.

	```lua
	local Preview = require(game.ReplicatedStorage.Packages.Spray.Preview)

	Preview.Play(nil, { Seed = 1 })
	Preview.Scrub(0.15) -- the burst 0.15 seconds in
	```

	Each call starts a fresh burst, so without the `Seed` option you get different particles
	every time you scrub. After editing a property, call [Preview.Play] and then `Scrub`
	again to see the change.

	Needs a preview started with [Preview.Play] first.

	@param Time number -- Seconds into the burst.
	@return string -- A message saying the moment and how many emitters were frozen.
]=]
function Preview.Scrub(Time: number): string
	if #entries == 0 then
		return "Spray preview: nothing playing. Call .Play() first."
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, entry in entries do
		entry.Effect:Pause()
		entry.Effect:Emit(entry.Count)
		entry.Effect:Pause()
		entry.Effect:SetTime(Time)
	end
	return ("Spray preview: frozen at %.3fs across %d emitter(s)."):format(Time, #entries)
end

--[=[
	Moves the frozen moment by `Delta` seconds. Negative values go back. Use it after
	[Preview.Scrub] to go through a burst a little at a time, for example to find the exact
	moment a curve starts looking wrong.

	```lua
	Preview.Scrub(0)
	Preview.Step(0.02) -- run this line a few times
	```

	Call [Preview.Scrub] first. Without it, `Step` stops new bursts from firing, but the burst
	already on screen keeps playing.

	@param Delta number -- Seconds to move. Negative values go back.
	@return string -- A message saying how far it moved.
]=]
function Preview.Step(Delta: number): string
	if #entries == 0 then
		return "Spray preview: nothing playing. Call .Play() first."
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for _, entry in entries do
		entry.Effect:Forward(Delta)
	end
	return ("Spray preview: stepped %+.3fs."):format(Delta)
end

--[=[
	Unfreezes the preview after [Preview.Scrub] or [Preview.Step]. The frozen burst plays out
	from where it stopped, and new bursts start again after the usual interval.

	@return string -- A message saying the preview is looping again.
]=]
function Preview.Resume(): string
	if #entries == 0 then
		return "Spray preview: nothing playing. Call .Play() first."
	end
	for _, entry in entries do
		entry.Effect:Resume()
	end
	if not connection then
		elapsed = 0
		connection = RunService.Heartbeat:Connect(function(delta: number)
			elapsed += delta
			if elapsed < interval then
				return
			end
			elapsed = 0
			for _, entry in entries do
				entry.Effect:Emit(entry.Count)
			end
		end)
	end
	return ("Spray preview: looping again every %.2fs."):format(interval)
end

return Preview

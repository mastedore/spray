--!strict
-->> Scheduler.luau
--> A single RenderStepped connection shared by every Spray in the game, instead of one
--> per Spray.
-->
--> Having lots of these on screen is normal (the circular minigame alone runs nine), and
--> with one connection each, the engine would walk a list of nine connections to do what a
--> single loop over nine entries already does. The connection also only exists while
--> something needs it, so a Spray sitting paused between bursts costs nothing.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local RunService = game:GetService("RunService")

--- Anything with a clock to advance, which in practice is always a Spray. It's left untyped
--- on purpose because Spray requires this module, so using the Spray type here would make a
--- cycle and neither type would resolve. The registry is private to the package, so nothing
--- outside can put the wrong thing in it.
export type Steppable = any

local Scheduler = {}

local members: { [any]: true } = {}
local population = 0
local connection: RBXScriptConnection? = nil

local function Step(DeltaTime: number)
	-- No need to copy the set before looping. A Spray never adds or removes another Spray
	-- during its own step, so the set can't change while we iterate over it.
	for member in members do
		member:Advance(DeltaTime)
	end
end

local function Connect()
	-- RenderStepped only works on the client. A Spray on the server has nothing to draw
	-- to, but plugins and edit-mode tools do run this code, so we fall back to Heartbeat
	-- instead of erroring.
	if RunService:IsClient() then
		connection = RunService.RenderStepped:Connect(Step)
	else
		connection = RunService.Heartbeat:Connect(Step)
	end
end

function Scheduler.Add(Member: Steppable)
	if members[Member] then
		return
	end
	members[Member] = true
	population += 1
	if not connection then
		Connect()
	end
end

function Scheduler.Remove(Member: Steppable)
	if not members[Member] then
		return
	end
	members[Member] = nil
	population -= 1
	if population <= 0 and connection then
		connection:Disconnect()
		connection = nil
	end
end

return Scheduler

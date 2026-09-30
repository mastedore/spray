--!strict
-->> Group.luau
--> Several wrapped origins played as one, which is what the preview's Playback window
--> drives. The emitters of one effect are usually its layers, so they share a single
--> timeline: they start together, scrub together and loop together.
-->
--> Each member keeps its own seed and its own start burst (its BurstCount). The group owns
--> the end of the run: members are given a run that never ends by itself, and the group
--> restarts or stops all of them at once when its own duration is up.
-->
--> The timeline follows the first member's clock. A member with a different TimeScale
--> drifts from the rest within a run, because every Spray scales its own clock, and lines
--> up again at the next restart.

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local Origin = require(script.Parent.playground.Origin)

type Origin = Origin.Origin

--- Same cap as Origin's, for the same reason: Spray only remembers this many bursts.
const BURST_HISTORY = 64
const DEFAULT_EMIT = 20

local Group = {}
Group.__index = Group

export type Group = typeof(setmetatable({} :: {
	Name: string,
	Members: { Origin },
	Playing: boolean,
	Loop: boolean,
	Duration: number?, -- nil means automatic: the longest member's
	EmitCount: number,
	Bursts: { Origin.Burst }, -- for the timeline ticks only
	Revision: number,
	Destroyed: boolean,
}, Group))

local function Describe(Members: { Origin }): string
	local first = Members[1]
	if not first then
		return "nothing"
	end
	if #Members == 1 then
		return first.Name
	end
	return `{first.Name} + {#Members - 1} more`
end

local function Touch(self: Group)
	self.Revision += 1
end

function Group.New(Members: { Origin }): Group
	for _, member in Members do
		member.Loop = false
		member.Duration = math.huge
	end

	local first = Members[1]
	local self: Group = setmetatable({
		Name = Describe(Members),
		Members = Members,
		Playing = false,
		Loop = true,
		Duration = nil,
		EmitCount = if first then first.EmitCount else DEFAULT_EMIT,
		Bursts = {},
		Revision = 0,
		Destroyed = false,
	}, Group)

	self:Restart()
	return self
end

-- -- Queries -------------------------------------------------------------------

function Group.Clock(self: Group): number
	local leader = self.Members[1]
	return if leader then leader:Clock() else 0
end

function Group.AutoDuration(self: Group): number
	local longest = 0
	for _, member in self.Members do
		longest = math.max(longest, member:AutoDuration())
	end
	return math.max(longest, 0.05)
end

function Group.GetDuration(self: Group): number
	return self.Duration or self:AutoDuration()
end

--- The start burst every member shares, or nil when they don't all have the same one.
function Group.GetBurstCount(self: Group): number?
	local shared: number? = nil
	for _, member in self.Members do
		local own = member:GetBurstCount()
		if shared == nil then
			shared = own
		elseif shared ~= own then
			return nil
		end
	end
	return shared or 0
end

--- Writes BurstCount on every member. These are emitters in the open place, so the edit is
--- recorded for undo like any other.
function Group.SetBurstCount(self: Group, Count: number)
	local recording = ChangeHistoryService:TryBeginRecording("Set BurstCount")
	for _, member in self.Members do
		member:SetBurstCount(Count)
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
end

-- -- Transport -----------------------------------------------------------------

--- Restarts every member from zero, together. Same `KeepPaused` rule as Origin.Restart.
function Group.Restart(self: Group, KeepPaused: boolean?)
	local resume = not (KeepPaused and not self.Playing)

	table.clear(self.Bursts)
	local total = 0
	for _, member in self.Members do
		member:Restart()
		if not resume then
			member:Pause()
		end
		total += member:GetBurstCount()
	end
	if total > 0 then
		table.insert(self.Bursts, { Time = 0, Count = total })
	end

	self.Playing = resume
	Touch(self)
end

function Group.Play(self: Group)
	if self.Playing then
		return
	end
	if self:Clock() >= self:GetDuration() - 1e-3 then
		self:Restart()
		return
	end
	for _, member in self.Members do
		member:Play()
	end
	self.Playing = true
end

function Group.Pause(self: Group)
	if not self.Playing then
		return
	end
	for _, member in self.Members do
		member:Pause()
	end
	self.Playing = false
end

function Group.Toggle(self: Group)
	if self.Playing then
		self:Pause()
	else
		self:Play()
	end
end

function Group.Seek(self: Group, Time: number)
	local time = math.clamp(Time, 0, self:GetDuration())
	for _, member in self.Members do
		member:Seek(time)
	end
end

function Group.Step(self: Group, Delta: number)
	self:Pause()
	for _, member in self.Members do
		member:Step(Delta)
	end
	local duration = self:GetDuration()
	if self:Clock() > duration then
		self:Seek(duration)
	end
end

--- `Count` more particles from every member, now.
function Group.Emit(self: Group, Count: number)
	if Count <= 0 then
		return
	end
	if not self.Playing then
		self:Restart()
	end
	table.insert(self.Bursts, { Time = self:Clock(), Count = Count * #self.Members })
	if #self.Bursts > BURST_HISTORY then
		table.remove(self.Bursts, 1)
	end
	for _, member in self.Members do
		member:Emit(Count)
	end
	Touch(self)
end

--- Once a frame: pending rebuilds on the members, then the end of the run.
function Group.Update(self: Group, Now: number)
	for _, member in self.Members do
		member:Update(Now)
	end

	if not self.Playing then
		return
	end
	local duration = self:GetDuration()
	if self:Clock() < duration then
		return
	end
	if self.Loop then
		self:Restart()
	else
		self:Pause()
		self:Seek(duration)
	end
end

-- -- Membership ----------------------------------------------------------------

--- Lets go of one member, for when its emitter left the UI or the place.
function Group.Drop(self: Group, Member: Origin)
	local index = table.find(self.Members, Member)
	if not index then
		return
	end
	table.remove(self.Members, index)
	Member:Destroy()
	self.Name = Describe(self.Members)
	Touch(self)
end

function Group.Destroy(self: Group)
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	for _, member in self.Members do
		member:Destroy()
	end
	table.clear(self.Members)
end

return Group

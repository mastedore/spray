--!strict
-->> PlaybackPanel.luau
--> The transport for the selected origin: play and pause, restart, frame steps, loop, emit,
--> and a timeline that scrubs like the seek bar of a music player - except that what it
--> moves is the Spray's clock, so the particles go back and forth with it.
-->
--> The panel reads the origin every frame instead of being told about changes, because the
--> clock moves on its own and a looping origin restarts by itself.
-->
--> What it drives doesn't have to be an origin. Anything shaped like a Transport will do,
--> which is how the plugin's preview puts this same panel over the emitters selected in
--> Studio, several of them in step, in a widget of its own.

local RunService = game:GetService("RunService")

local Drag = require(script.Parent.Drag)
local Input = require(script.Parent.Input)
local Stage = require(script.Parent.Stage)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

const FRAME = 1 / 60

--- What the panel needs from the thing it drives. Origin is one; so is the plugin's Group.
--- GetBurstCount may say nil when there is no single answer, and the field then goes blank.
export type Transport = {
	Name: string,
	Playing: boolean,
	Loop: boolean,
	Duration: number?,
	EmitCount: number,
	Bursts: { { Time: number, Count: number } },
	Revision: number,
	Destroyed: boolean,

	Clock: (self: any) -> number,
	GetDuration: (self: any) -> number,
	GetBurstCount: (self: any) -> number?,
	SetBurstCount: (self: any, Count: number) -> (),
	Restart: (self: any, KeepPaused: boolean?) -> (),
	Play: (self: any) -> (),
	Pause: (self: any) -> (),
	Toggle: (self: any) -> (),
	Seek: (self: any, Time: number) -> (),
	Step: (self: any, Delta: number) -> (),
	Emit: (self: any, Count: number) -> (),
}

export type Options = {
	--- Read every frame. Defaults to the origin selected on the stage.
	Target: (() -> Transport?)?,
	--- Builds into this instead of a window of its own.
	Parent: GuiObject?,
	--- Shows the title somewhere other than the window's title bar.
	Title: ((Text: string) -> ())?,
}

local PlaybackPanel = {}

function PlaybackPanel.Build(Config: Options?)
	local options: Options = Config or {}
	local Target: () -> Transport? = options.Target or function()
		return Stage.Selected :: any
	end

	local body: GuiObject
	local SetTitle: (string) -> ()
	local parent = options.Parent
	if parent then
		body = parent
		SetTitle = options.Title or function() end
	else
		local window = Widgets.Window(
			"Playback",
			UDim2.new(0.5, 0, 1, -12),
			Vector2.new(0.5, 1),
			UDim2.fromOffset(600, 150)
		)
		body = window.Body
		SetTitle = function(Text)
			window.Title.Text = Text
		end
	end

	-- -- Transport row ----------------------------------------------------------

	local transport: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = Widgets.NextOrder(body),
		Parent = body,
	})
	local buttons: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -130, 1, 0),
		Parent = transport,
	}, {
		Widgets.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})

	local function Button(Text: string, Width: number): TextButton
		return Widgets.Button(Text, {
			Size = UDim2.new(0, Width, 1, 0),
			LayoutOrder = Widgets.NextOrder(buttons),
			Parent = buttons,
		})
	end

	local restart = Button("Restart", 62)
	local back = Button("-1f", 36)
	local play = Button("Pause", 70)
	local forward = Button("+1f", 36)
	local loopHolder: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 84, 1, 0),
		LayoutOrder = Widgets.NextOrder(buttons),
		Parent = buttons,
	})
	local loop = Widgets.Toggle(loopHolder, "Loop: On", "Loop: Off", UDim2.fromScale(1, 1))
	local emit = Button("Emit", 50)
	local emitHolder: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 52, 1, 0),
		LayoutOrder = Widgets.NextOrder(buttons),
		Parent = buttons,
	})
	local emitCount = Widgets.NumberField(emitHolder, { Integer = true, Min = 1, Max = 5000, Step = 0.2 })

	play.BackgroundColor3 = Theme.AccentDim

	local clockLabel = Widgets.Label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 124, 1, 0),
		Font = Theme.FontMedium,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = transport,
	})

	-- -- Timeline ---------------------------------------------------------------

	local timeline: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = Widgets.NextOrder(body),
		Parent = body,
	})
	local track: Frame = Widgets.Create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Size = UDim2.new(1, -14, 0, 8),
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		Parent = timeline,
	}, { Widgets.Corner(4), Widgets.Outline(Theme.Stroke, 0.4) })
	local fill: Frame = Widgets.Create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { Widgets.Corner(4) })
	local ticks: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = track,
	})
	local handle: Frame = Widgets.Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Theme.Text,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = track,
	}, { Widgets.Corner(7), Widgets.Outline(Theme.Window, 0) })
	local hit: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = timeline,
	})

	-- -- Options row ------------------------------------------------------------

	local optionsRow: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = Widgets.NextOrder(body),
		Parent = body,
	}, {
		Widgets.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
		}),
	})
	local function Caption(Text: string, Width: number): TextLabel
		return Widgets.Label({
			Text = Text,
			TextColor3 = Theme.TextDim,
			Size = UDim2.new(0, Width, 1, 0),
			LayoutOrder = Widgets.NextOrder(optionsRow),
			Parent = optionsRow,
		})
	end
	local function Holder(Width: number): Frame
		return Widgets.Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(0, Width, 1, 0),
			LayoutOrder = Widgets.NextOrder(optionsRow),
			Parent = optionsRow,
		})
	end

	local durationCaption = Caption("Duration", 58)
	local duration = Widgets.NumberField(Holder(92), { Min = 0.05, Max = 120, Step = 0.01, AllowEmpty = true, Placeholder = "auto" }, durationCaption)
	local burstCaption = Caption("Start burst", 70)
	local startBurst = Widgets.NumberField(Holder(56), { Integer = true, Min = 0, Max = 5000, Step = 0.2, Placeholder = "mixed" }, burstCaption)
	Widgets.Label({
		Text = "Space: play / pause",
		TextSize = Theme.SmallTextSize,
		TextColor3 = Theme.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, 170, 1, 0),
		LayoutOrder = Widgets.NextOrder(optionsRow),
		Parent = optionsRow,
	})

	-- -- Wiring -----------------------------------------------------------------

	restart.Activated:Connect(function()
		local origin = Target()
		if origin then
			origin:Restart(true)
		end
	end)
	play.Activated:Connect(function()
		local origin = Target()
		if origin then
			origin:Toggle()
		end
	end)
	back.Activated:Connect(function()
		local origin = Target()
		if origin then
			origin:Step(-FRAME)
		end
	end)
	forward.Activated:Connect(function()
		local origin = Target()
		if origin then
			origin:Step(FRAME)
		end
	end)
	loop.Changed = function(value)
		local origin = Target()
		if origin then
			origin.Loop = value
		end
	end
	emit.Activated:Connect(function()
		local origin = Target()
		if origin then
			origin:Emit(origin.EmitCount)
		end
	end)
	emitCount.Changed = function(value)
		local origin = Target()
		if origin and value then
			origin.EmitCount = value
		end
	end
	duration.Changed = function(value)
		local origin = Target()
		if origin then
			origin.Duration = value
		end
	end
	startBurst.Changed = function(value)
		local origin = Target()
		if origin and value then
			origin:SetBurstCount(value)
		end
	end

	-- Scrubbing holds the effect paused under the pointer and puts it back how it was on
	-- release, the way dragging a seek bar does.
	Widgets.Press(hit, function(input)
		local origin = Target()
		if not origin then
			return
		end
		local wasPlaying = origin.Playing
		origin:Pause()
		local function At(Point: Vector2)
			if origin.Destroyed then
				return
			end
			local fraction = math.clamp((Point.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
			origin:Seek(fraction * origin:GetDuration())
		end
		At(Drag.Point(input))
		Drag.Follow(input, At, function()
			if wasPlaying and not origin.Destroyed then
				origin:Play()
			end
		end)
	end)

	Input.Began:Connect(function(input: InputObject, processed: boolean, root: Instance?)
		if processed or input.KeyCode ~= Enum.KeyCode.Space then
			return
		end
		if Input.Typing() or not Input.Within(root, body) then
			return
		end
		local origin = Target()
		if origin then
			origin:Toggle()
		end
	end)

	-- -- Per frame --------------------------------------------------------------

	local shownRevision = -1
	local shownDuration = -1
	local shownOrigin: any = nil

	local function DrawTicks(Bursts: { { Time: number, Count: number } }, Length: number)
		ticks:ClearAllChildren()
		for _, burst in Bursts do
			Widgets.Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(math.clamp(burst.Time / Length, 0, 1), 0.5),
				Size = UDim2.new(0, 2, 1, 8),
				BackgroundColor3 = Theme.TextDim,
				BorderSizePixel = 0,
				Parent = ticks,
			})
		end
	end

	RunService.RenderStepped:Connect(function()
		local origin = Target()
		if origin and origin.Destroyed then
			origin = nil
		end
		SetTitle(if origin then `Playback · {origin.Name}` else "Playback")
		if not origin then
			clockLabel.Text = "-"
			fill.Size = UDim2.fromScale(0, 1)
			handle.Position = UDim2.fromScale(0, 0.5)
			ticks:ClearAllChildren()
			shownOrigin = nil
			return
		end

		local length = origin:GetDuration()
		local clock = math.clamp(origin:Clock(), 0, length)
		local fraction = clock / length
		fill.Size = UDim2.fromScale(fraction, 1)
		handle.Position = UDim2.fromScale(fraction, 0.5)
		clockLabel.Text = string.format("%.2f / %.2f s", clock, length)

		play.Text = if origin.Playing then "Pause" else "Play"
		loop.Set(origin.Loop)
		emitCount.Set(origin.EmitCount)
		duration.Set(origin.Duration)
		startBurst.Set(origin:GetBurstCount())

		if shownOrigin ~= origin or shownRevision ~= origin.Revision or shownDuration ~= length then
			shownOrigin = origin
			shownRevision = origin.Revision
			shownDuration = length
			DrawTicks(origin.Bursts, length)
		end
	end)
end

return PlaybackPanel

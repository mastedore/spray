--!strict
-->> NumberSequenceField.luau
--> A curve editor for the NumberSequence properties: Size, Squash and Transparency.
-->
--> The row shows a one-line summary; clicking it opens the graph underneath. On the graph:
--> click empty space to add a keypoint, drag a keypoint to move it, right-click one to
--> delete it. The selected keypoint's time, value and envelope can also be typed, or
--> scrubbed by dragging their captions. The shaded lines either side of the curve are the
--> envelope, the per-particle random band Spray rolls once for each particle.
-->
--> The vertical range is only reframed when told to (switching origins) or when a typed
--> value falls outside it. Reframing on every edit would make a keypoint dragged to the top
--> push the range up under the cursor, forever.

local Drag = require(script.Parent.Drag)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Field<T> = Widgets.Field<T>

--- How the vertical axis is framed. Unit is fixed at 0..1 (Transparency); Positive runs
--- from zero up to whatever fits (Size); Symmetric is centred on zero (Squash).
export type Range = "Unit" | "Positive" | "Symmetric"

type Key = {
	Time: number,
	Value: number,
	Envelope: number,
}

const MAX_KEYPOINTS = 20 -- the engine's own cap
const GRAPH_HEIGHT = 110
const HIT_RADIUS = 9
const MIN_GAP = 0.001
const NICE_TOPS = { 0.25, 0.5, 1, 2, 3, 5, 10, 20, 50, 100 }

local Create = Widgets.Create

local NumberSequenceField = {}

local function NiceTop(Magnitude: number): number
	for _, top in NICE_TOPS do
		if Magnitude <= top then
			return top
		end
	end
	return math.ceil(Magnitude)
end

function NumberSequenceField.New(Parent: Instance, Label: string, Range: Range): Field<NumberSequence>
	local _, _, content = Widgets.Row(Parent, Label)
	local summary = Widgets.Button("", {
		Size = UDim2.fromScale(1, 1),
		Font = Theme.Font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = content,
	})
	Widgets.Padding(8).Parent = summary

	local editor: Frame = Create("Frame", {
		Name = Label .. "Editor",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, GRAPH_HEIGHT + 60),
		LayoutOrder = Widgets.NextOrder(Parent),
		Visible = false,
		Parent = Parent,
	})

	local canvas: Frame = Create("Frame", {
		Name = "Canvas",
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, GRAPH_HEIGHT),
		Parent = editor,
	}, { Widgets.Corner(4), Widgets.Outline(Theme.Stroke, 0.4) })

	local grid: Frame = Create("Frame", { Name = "Grid", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = canvas })
	local plot: Frame = Create("Frame", { Name = "Plot", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = canvas })
	local topLabel = Widgets.Label({
		TextSize = 11,
		TextColor3 = Theme.TextFaint,
		Position = UDim2.fromOffset(4, 1),
		Size = UDim2.fromOffset(60, 12),
		ZIndex = 3,
		Parent = canvas,
	})
	local bottomLabel = Widgets.Label({
		TextSize = 11,
		TextColor3 = Theme.TextFaint,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 4, 1, -1),
		Size = UDim2.fromOffset(60, 12),
		ZIndex = 3,
		Parent = canvas,
	})
	-- Wider than the canvas so keypoints sitting on its edge can still be grabbed.
	local hit: Frame = Create("Frame", {
		Name = "Hit",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-HIT_RADIUS, -HIT_RADIUS),
		Size = UDim2.new(1, HIT_RADIUS * 2, 1, HIT_RADIUS * 2),
		ZIndex = 5,
		Parent = canvas,
	})

	-- The t / v / e fields, leaving room on the right for the Delete button.
	local controls: Frame = Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, GRAPH_HEIGHT + 8),
		Size = UDim2.new(1, -58, 0, 22),
		Parent = editor,
	})
	local function Cell(Index: number, Caption: string, Options: Widgets.NumberOptions): Field<number?>
		local cell: Frame = Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new((Index - 1) / 3, 0, 0, 0),
			Size = UDim2.new(1 / 3, -4, 1, 0),
			Parent = controls,
		})
		local grip = Widgets.Label({
			Text = Caption,
			TextSize = Theme.SmallTextSize,
			TextColor3 = Theme.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, 14, 1, 0),
			Parent = cell,
		})
		return Widgets.NumberField(cell, Options, grip, UDim2.new(1, -14, 1, 0), UDim2.fromOffset(14, 0))
	end
	local timeField = Cell(1, "t", { Min = 0, Max = 1, Step = 0.002 })
	local valueField = Cell(2, "v", { Step = 0.005 })
	local envelopeField = Cell(3, "e", { Min = 0, Step = 0.002 })
	local remove = Widgets.Button("Delete", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, GRAPH_HEIGHT + 8),
		Size = UDim2.fromOffset(54, 22),
		TextSize = Theme.SmallTextSize,
		Parent = editor,
	})
	Widgets.Label({
		Text = "Click: add  ·  drag: move  ·  right-click: delete",
		TextSize = 12,
		TextColor3 = Theme.TextFaint,
		Position = UDim2.fromOffset(0, GRAPH_HEIGHT + 36),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = editor,
	})

	local keys: { Key } = { { Time = 0, Value = 0, Envelope = 0 }, { Time = 1, Value = 0, Envelope = 0 } }
	local selected = 1
	local low, high = 0, 1
	local field: Field<NumberSequence> = { Set = nil :: any, Changed = nil }

	-- -- Framing ---------------------------------------------------------------

	local function Fit()
		if Range == "Unit" then
			low, high = 0, 1
			return
		end
		local magnitude = 0
		for _, key in keys do
			magnitude = math.max(magnitude, math.abs(key.Value) + key.Envelope)
		end
		if Range == "Symmetric" then
			high = NiceTop(math.max(magnitude * 1.1, 1))
			low = -high
		else
			low = 0
			high = NiceTop(math.max(magnitude * 1.15, 0.25))
		end
	end

	local function Fits(): boolean
		for _, key in keys do
			if key.Value < low or key.Value > high then
				return false
			end
		end
		return true
	end

	--- Scale coordinates of a point on the graph.
	local function Place(Time: number, Value: number): Vector2
		local normal = math.clamp((Value - low) / (high - low), 0, 1)
		return Vector2.new(Time, 1 - normal)
	end

	local function Sample(Point: Vector2): (number, number)
		local position, size = canvas.AbsolutePosition, canvas.AbsoluteSize
		local time = math.clamp((Point.X - position.X) / size.X, 0, 1)
		local value = low + (1 - (Point.Y - position.Y) / size.Y) * (high - low)
		return time, math.clamp(value, low, high)
	end

	-- -- Drawing ---------------------------------------------------------------

	local function Segment(A: Vector2, B: Vector2, Color: Color3, Transparency: number, Thickness: number)
		local delta = B - A
		Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((A.X + B.X) / 2, (A.Y + B.Y) / 2),
			Size = UDim2.fromOffset(delta.Magnitude + 1, Thickness),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = Color,
			BackgroundTransparency = Transparency,
			BorderSizePixel = 0,
			Parent = plot,
		})
	end

	local function DrawGrid()
		grid:ClearAllChildren()
		for step = 1, 3 do
			Create("Frame", {
				BackgroundColor3 = Theme.Stroke,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, step / 4),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = grid,
			})
			Create("Frame", {
				BackgroundColor3 = Theme.Stroke,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(step / 4, 0),
				Size = UDim2.new(0, 1, 1, 0),
				Parent = grid,
			})
		end
		if low < 0 and high > 0 then
			Create("Frame", {
				BackgroundColor3 = Theme.TextFaint,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, Place(0, 0).Y),
				Size = UDim2.new(1, 0, 0, 1),
				Parent = grid,
			})
		end
		topLabel.Text = Widgets.Format(high)
		bottomLabel.Text = Widgets.Format(low)
	end

	local function Summarise(): string
		local first = keys[1]
		local constant = true
		for _, key in keys do
			if key.Value ~= first.Value or key.Envelope ~= 0 then
				constant = false
				break
			end
		end
		local arrow = if editor.Visible then "^" else "v"
		if constant then
			return `{Widgets.Format(first.Value)}   {arrow}`
		end
		return `{#keys} keys: {Widgets.Format(first.Value)} → {Widgets.Format(keys[#keys].Value)}   {arrow}`
	end

	local function Redraw()
		summary.Text = Summarise()

		local key = keys[selected]
		timeField.Set(key.Time)
		valueField.Set(key.Value)
		envelopeField.Set(key.Envelope)

		if not editor.Visible then
			return
		end

		plot:ClearAllChildren()
		-- Lines are laid out in the window's unscaled pixels, since that is what Offset
		-- means inside a UIScale.
		local size = canvas.AbsoluteSize / Theme.Scale
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local function Pixel(Time: number, Value: number): Vector2
			local place = Place(Time, Value)
			return Vector2.new(place.X * size.X, place.Y * size.Y)
		end

		for index = 1, #keys - 1 do
			local a, b = keys[index], keys[index + 1]
			if a.Envelope > 0 or b.Envelope > 0 then
				Segment(Pixel(a.Time, a.Value + a.Envelope), Pixel(b.Time, b.Value + b.Envelope), Theme.Accent, 0.65, 1)
				Segment(Pixel(a.Time, a.Value - a.Envelope), Pixel(b.Time, b.Value - b.Envelope), Theme.Accent, 0.65, 1)
			end
			Segment(Pixel(a.Time, a.Value), Pixel(b.Time, b.Value), Theme.Accent, 0, 2)
		end

		for index, point in keys do
			Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(Place(point.Time, point.Value).X, Place(point.Time, point.Value).Y),
				Size = UDim2.fromOffset(9, 9),
				BackgroundColor3 = if index == selected then Theme.Text else Theme.Accent,
				BorderSizePixel = 0,
				ZIndex = 2,
				Parent = plot,
			}, { Widgets.Corner(5), Widgets.Outline(Theme.Field, 0) })
		end
	end

	-- -- Editing ---------------------------------------------------------------

	local function Commit()
		Redraw()
		if not field.Changed then
			return
		end
		local points = table.create(#keys)
		for index, key in keys do
			points[index] = NumberSequenceKeypoint.new(key.Time, key.Value, key.Envelope)
		end
		field.Changed(NumberSequence.new(points))
	end

	--- Moves the selected keypoint, keeping the ends pinned to 0 and 1 and the middle ones
	--- between their neighbours - NumberSequence refuses anything out of order.
	local function Move(Time: number?, Value: number?)
		local key = keys[selected]
		if Time then
			if selected == 1 then
				Time = 0
			elseif selected == #keys then
				Time = 1
			else
				Time = math.clamp(Time, keys[selected - 1].Time + MIN_GAP, keys[selected + 1].Time - MIN_GAP)
			end
			key.Time = Time
		end
		if Value then
			key.Value = Value
		end
	end

	local function Remove(Index: number)
		if Index == 1 or Index == #keys then
			return
		end
		table.remove(keys, Index)
		selected = math.min(selected, #keys)
		if selected == Index then
			selected = math.max(1, Index - 1)
		end
		Commit()
	end

	Widgets.Press(hit, function(input)
		local point = Drag.Point(input)

		local nearest, distance = 1, math.huge
		for index, key in keys do
			local place = Place(key.Time, key.Value)
			local screen = canvas.AbsolutePosition + place * canvas.AbsoluteSize
			local gap = (screen - point).Magnitude
			if gap < distance then
				nearest, distance = index, gap
			end
		end
		local grabbed = distance <= HIT_RADIUS * Theme.Scale

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if grabbed then
				Remove(nearest)
			end
			return
		end

		if not grabbed then
			if #keys >= MAX_KEYPOINTS then
				return
			end
			local time, value = Sample(point)
			time = math.clamp(time, MIN_GAP, 1 - MIN_GAP)
			local slot = #keys
			for index, key in keys do
				if key.Time > time then
					slot = index
					break
				end
			end
			-- Never on top of an existing time, which would be out of order.
			time = math.clamp(time, keys[slot - 1].Time + MIN_GAP, keys[slot].Time - MIN_GAP)
			table.insert(keys, slot, { Time = time, Value = value, Envelope = 0 })
			nearest = slot
		end

		selected = nearest
		Commit()

		Drag.Follow(input, function(position)
			local time, value = Sample(position)
			Move(time, value)
			Commit()
		end)
	end, true)

	timeField.Changed = function(value)
		if value then
			Move(value, nil)
			Commit()
		end
	end
	valueField.Changed = function(value)
		if value then
			Move(nil, value)
			if not Fits() then
				Fit()
				DrawGrid()
			end
			Commit()
		end
	end
	envelopeField.Changed = function(value)
		keys[selected].Envelope = math.max(value or 0, 0)
		Commit()
	end
	remove.Activated:Connect(function()
		Remove(selected)
	end)

	summary.Activated:Connect(function()
		editor.Visible = not editor.Visible
		DrawGrid()
		Redraw()
	end)
	canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(Redraw)

	function field.Set(Value: NumberSequence, Refit: boolean?)
		local fresh: { Key } = {}
		for _, keypoint in Value.Keypoints do
			table.insert(fresh, { Time = keypoint.Time, Value = keypoint.Value, Envelope = keypoint.Envelope })
		end
		keys = fresh
		selected = math.clamp(selected, 1, #keys)
		if Refit or not Fits() then
			Fit()
			DrawGrid()
		end
		Redraw()
	end

	Fit()
	DrawGrid()
	return field
end

return NumberSequenceField

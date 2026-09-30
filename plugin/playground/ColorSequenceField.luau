--!strict
-->> ColorSequenceField.luau
--> A gradient editor for ParticleEmitter.Color.
-->
--> The row shows the gradient itself; clicking it opens the editor underneath. Click the
--> bar to add a colour stop there, drag a stop's marker to move it, right-click a marker to
--> delete it. The selected stop is coloured with the hex box or the H, S and V sliders.
-->
--> The picker keeps its own hue and saturation rather than reading them back from the
--> colour every time, because a grey or a black has no hue to read back: drag S or V to zero
--> and the hue would reset to red under the next edit.

local Drag = require(script.Parent.Drag)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Field<T> = Widgets.Field<T>

type Key = {
	Time: number,
	Color: Color3,
}

const MAX_KEYPOINTS = 20
const BAR_HEIGHT = 22
const MARKER_TOP = BAR_HEIGHT + 3
const GRAB_RADIUS = 7
const MIN_GAP = 0.001

local Create = Widgets.Create

local ColorSequenceField = {}

local function Rainbow(): ColorSequence
	local points = {}
	for step = 0, 6 do
		table.insert(points, ColorSequenceKeypoint.new(step / 6, Color3.fromHSV((step / 6) % 1, 1, 1)))
	end
	return ColorSequence.new(points)
end

--- Linear in RGB, which is how the engine and Spray's Sampling.Color both read a sequence.
local function Sample(Keys: { Key }, Time: number): Color3
	for index = 1, #Keys - 1 do
		local current, following = Keys[index], Keys[index + 1]
		if Time <= following.Time then
			local span = following.Time - current.Time
			local alpha = if span > 0 then (Time - current.Time) / span else 0
			return current.Color:Lerp(following.Color, alpha)
		end
	end
	return Keys[#Keys].Color
end

local function Build(Keys: { Key }): ColorSequence
	local points = table.create(#Keys)
	for index, key in Keys do
		points[index] = ColorSequenceKeypoint.new(key.Time, key.Color)
	end
	return ColorSequence.new(points)
end

function ColorSequenceField.New(Parent: Instance, Label: string): Field<ColorSequence>
	local _, _, content = Widgets.Row(Parent, Label)
	local preview = Widgets.Button("", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = content,
	})
	local previewGradient: UIGradient = Create("UIGradient", { Parent = preview })

	local editor: Frame = Create("Frame", {
		Name = Label .. "Editor",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 156),
		LayoutOrder = Widgets.NextOrder(Parent),
		Visible = false,
		Parent = Parent,
	})

	local bar: Frame = Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		Parent = editor,
	}, { Widgets.Corner(4), Widgets.Outline(Theme.Stroke, 0.3) })
	local barGradient: UIGradient = Create("UIGradient", { Parent = bar })
	local markers: Frame = Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, MARKER_TOP),
		Size = UDim2.new(1, 0, 0, 12),
		Parent = editor,
	})
	local hit: Frame = Create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-GRAB_RADIUS, -2),
		Size = UDim2.new(1, GRAB_RADIUS * 2, 0, MARKER_TOP + 14),
		ZIndex = 5,
		Parent = editor,
	})

	local swatch: Frame = Create("Frame", {
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.fromOffset(22, 22),
		Parent = editor,
	}, { Widgets.Corner(4), Widgets.Outline(Theme.Stroke, 0) })
	local hexField = Widgets.TextField(editor, "#ffffff", UDim2.fromOffset(90, 22), UDim2.fromOffset(28, 46))
	local remove = Widgets.Button("Delete", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 46),
		Size = UDim2.fromOffset(54, 22),
		TextSize = Theme.SmallTextSize,
		Parent = editor,
	})

	local function SliderRow(Caption: string, Y: number): Widgets.Slider
		Widgets.Label({
			Text = Caption,
			TextSize = Theme.SmallTextSize,
			TextColor3 = Theme.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(0, Y),
			Size = UDim2.fromOffset(14, 14),
			Parent = editor,
		})
		return Widgets.Slider(editor, UDim2.new(1, -22, 0, 12), UDim2.fromOffset(20, Y + 1))
	end
	local hueSlider = SliderRow("h", 78)
	local saturationSlider = SliderRow("s", 98)
	local valueSlider = SliderRow("v", 118)
	hueSlider.Gradient.Color = Rainbow()

	Widgets.Label({
		Text = "Click bar: add  ·  drag marker: move  ·  right-click: delete",
		TextSize = 12,
		TextColor3 = Theme.TextFaint,
		Position = UDim2.fromOffset(0, 138),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = editor,
	})

	local keys: { Key } = { { Time = 0, Color = Color3.new(1, 1, 1) }, { Time = 1, Color = Color3.new(1, 1, 1) } }
	local selected = 1
	local hue, saturation, value = 0, 0, 1
	local field: Field<ColorSequence> = { Set = nil :: any, Changed = nil }

	local function Pick()
		hue, saturation, value = keys[selected].Color:ToHSV()
	end

	local function Redraw()
		local sequence = Build(keys)
		previewGradient.Color = sequence
		barGradient.Color = sequence

		local color = keys[selected].Color
		swatch.BackgroundColor3 = color
		hexField.Set("#" .. color:ToHex())
		hueSlider.Set(hue)
		saturationSlider.Set(saturation)
		valueSlider.Set(value)
		saturationSlider.Gradient.Color = ColorSequence.new(Color3.fromHSV(hue, 0, value), Color3.fromHSV(hue, 1, value))
		valueSlider.Gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(hue, saturation, 1))

		markers:ClearAllChildren()
		for index, key in keys do
			Create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(key.Time, 0),
				Size = UDim2.fromOffset(10, 12),
				BackgroundColor3 = key.Color,
				BorderSizePixel = 0,
				ZIndex = if index == selected then 2 else 1,
				Parent = markers,
			}, {
				Widgets.Corner(2),
				Create("UIStroke", {
					Color = if index == selected then Theme.Text else Theme.Stroke,
					Thickness = if index == selected then 2 else 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
		end
	end

	local function Commit()
		Redraw()
		if field.Changed then
			field.Changed(Build(keys))
		end
	end

	local function Recolor()
		keys[selected].Color = Color3.fromHSV(hue, saturation, value)
		Commit()
	end

	local function Select(Index: number)
		selected = Index
		Pick()
	end

	local function Remove(Index: number)
		if Index == 1 or Index == #keys then
			return
		end
		table.remove(keys, Index)
		Select(math.clamp(Index - 1, 1, #keys))
		Commit()
	end

	local function TimeAt(Point: Vector2): number
		return math.clamp((Point.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
	end

	Widgets.Press(hit, function(input)
		local point = Drag.Point(input)

		local nearest, distance = 1, math.huge
		for index, key in keys do
			local x = bar.AbsolutePosition.X + key.Time * bar.AbsoluteSize.X
			local gap = math.abs(x - point.X)
			-- Ties go to the later one so a stop dragged onto the end can be pulled back.
			if gap <= distance then
				nearest, distance = index, gap
			end
		end
		local grabbed = distance <= GRAB_RADIUS * Theme.Scale

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
			local time = math.clamp(TimeAt(point), MIN_GAP, 1 - MIN_GAP)
			local slot = #keys
			for index, key in keys do
				if key.Time > time then
					slot = index
					break
				end
			end
			time = math.clamp(time, keys[slot - 1].Time + MIN_GAP, keys[slot].Time - MIN_GAP)
			table.insert(keys, slot, { Time = time, Color = Sample(keys, time) })
			nearest = slot
		end

		Select(nearest)
		Commit()

		-- The two ends stay pinned to 0 and 1; they can be recoloured, not moved.
		if nearest == 1 or nearest == #keys then
			return
		end
		Drag.Follow(input, function(position)
			local index = selected
			if index == 1 or index == #keys then
				return
			end
			keys[index].Time = math.clamp(TimeAt(position), keys[index - 1].Time + MIN_GAP, keys[index + 1].Time - MIN_GAP)
			Commit()
		end)
	end, true)

	hueSlider.Changed = function(new)
		hue = new
		Recolor()
	end
	saturationSlider.Changed = function(new)
		saturation = new
		Recolor()
	end
	valueSlider.Changed = function(new)
		value = new
		Recolor()
	end
	hexField.Changed = function(text)
		local ok, color = pcall(Color3.fromHex, (string.gsub(text, "[#%s]", "")))
		if ok then
			keys[selected].Color = color
			Pick()
			Commit()
		else
			Redraw()
		end
	end
	remove.Activated:Connect(function()
		Remove(selected)
	end)

	preview.Activated:Connect(function()
		editor.Visible = not editor.Visible
	end)

	function field.Set(Sequence: ColorSequence, Refit: boolean?)
		local fresh: { Key } = {}
		for _, keypoint in Sequence.Keypoints do
			table.insert(fresh, { Time = keypoint.Time, Color = keypoint.Value })
		end
		keys = fresh
		selected = math.clamp(selected, 1, #keys)
		-- Only re-derive the picker when the colour really moved, so an echo of our own
		-- edit does not throw away the hue of a grey.
		local current = Color3.fromHSV(hue, saturation, value)
		local actual = keys[selected].Color
		local drift = math.abs(current.R - actual.R) + math.abs(current.G - actual.G) + math.abs(current.B - actual.B)
		if Refit or drift > 1e-3 then
			Pick()
		end
		Redraw()
	end

	Redraw()
	return field
end

return ColorSequenceField

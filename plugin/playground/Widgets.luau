--!strict
-->> Widgets.luau
--> The controls every playground panel is built from: windows that drag by their title bar,
--> labelled rows, and one field type per kind of value a ParticleEmitter property can hold.
-->
--> A FIELD is a table with a Set, which shows a value WITHOUT reporting it, and a Changed
--> callback, which fires only when the user edits it. Keeping the two directions apart is
--> what lets a panel rebind to another origin by calling Set on everything, without that
--> echo being mistaken for an edit and written straight back.
-->
--> Presses on anything that is not a button go through Widgets.Press, which drops the
--> press when another window, or an open dropdown, is on top at that point. Buttons do not
--> need it: Activated only ever reaches the topmost one.

local Drag = require(script.Parent.Drag)
local Input = require(script.Parent.Input)
local Theme = require(script.Parent.Theme)

--- How much of a window has to stay on screen, so it can always be dragged back.
const KEEP_VISIBLE = 56
const HEADER_HEIGHT = 30
const OPTION_HEIGHT = 24
const POPUP_MAX_HEIGHT = 280
const SCRUB_CURSOR = "rbxasset://SystemCursors/SizeEW"

export type Field<T> = {
	--- Shows a value without reporting it. `Refit` asks editors that keep a view range
	--- (the curve editor) to reframe it, which a panel does when switching origins.
	Set: (Value: T, Refit: boolean?) -> (),
	Changed: ((Value: T) -> ())?,
}

export type Window = {
	Frame: Frame,
	Body: ScrollingFrame,
	Title: TextLabel,
	Scale: UIScale,
	Size: UDim2,
	Collapsed: boolean,
}

export type NumberOptions = {
	Min: number?,
	Max: number?,
	Step: number?,      -- value change per pixel when scrubbing
	Integer: boolean?,
	Decimals: number?,
	AllowEmpty: boolean?, -- an empty box commits nil instead of snapping back
	Placeholder: string?,
}

local Widgets = {}

local panelsGui: GuiBase2d = nil :: any
local popupsGui: GuiBase2d = nil :: any
local windows: { Window } = {}
local topZ = 1
local closePopup: (() -> ())? = nil
local orders: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

-- -- Instances -----------------------------------------------------------------

function Widgets.Create(ClassName: string, Properties: { [string]: any }?, Children: { any }?): any
	local instance: any = Instance.new(ClassName)
	local parent: Instance? = nil
	if Properties then
		for key, value in Properties do
			if key == "Parent" then
				parent = value
			else
				instance[key] = value
			end
		end
	end
	if Children then
		for _, child in Children do
			child.Parent = instance
		end
	end
	-- Parented last, so the instance enters the tree fully configured.
	if parent then
		instance.Parent = parent
	end
	return instance
end

local Create = Widgets.Create

local function Merge(Defaults: { [string]: any }, Overrides: { [string]: any }?): { [string]: any }
	local merged = table.clone(Defaults)
	if Overrides then
		for key, value in Overrides do
			merged[key] = value
		end
	end
	return merged
end

function Widgets.Corner(Radius: number?): any
	return Create("UICorner", { CornerRadius = UDim.new(0, Radius or 5) })
end

function Widgets.Outline(Color: Color3?, Transparency: number?): any
	return Create("UIStroke", {
		Color = Color or Theme.Stroke,
		Transparency = Transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Widgets.Padding(Left: number, Right: number?, Top: number?, Bottom: number?): any
	return Create("UIPadding", {
		PaddingLeft = UDim.new(0, Left),
		PaddingRight = UDim.new(0, Right or Left),
		PaddingTop = UDim.new(0, Top or 0),
		PaddingBottom = UDim.new(0, Bottom or Top or 0),
	})
end

local Corner, Outline = Widgets.Corner, Widgets.Outline

--- LayoutOrder for the next thing added to `Parent`, so rows come out in the order they
--- were built without anyone numbering them by hand.
function Widgets.NextOrder(Parent: Instance): number
	local order = (orders[Parent] or 0) + 1
	orders[Parent] = order
	return order
end

function Widgets.Label(Properties: { [string]: any }?): TextLabel
	return Create("TextLabel", Merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, Properties))
end

function Widgets.Button(Text: string, Properties: { [string]: any }?): TextButton
	local stroke = Outline(Theme.Stroke, 0.5)
	local button: TextButton = Create("TextButton", Merge({
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Button,
		BorderSizePixel = 0,
		Font = Theme.FontMedium,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		Text = Text,
	}, Properties), { Corner(), stroke })
	-- Hover lights the outline rather than the fill, so buttons whose fill means something
	-- (toggles, the selected origin) keep showing it.
	button.MouseEnter:Connect(function()
		stroke.Color = Theme.TextDim
		stroke.Transparency = 0
	end)
	button.MouseLeave:Connect(function()
		stroke.Color = Theme.Stroke
		stroke.Transparency = 0.5
	end)
	return button
end

function Widgets.Box(Properties: { [string]: any }?): TextBox
	local stroke = Outline(Theme.Stroke, 0.4)
	local box: TextBox = Create("TextBox", Merge({
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = Theme.Font,
		TextSize = Theme.TextSize,
		TextColor3 = Theme.Text,
		PlaceholderColor3 = Theme.TextFaint,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}, Properties), { Corner(4), Widgets.Padding(6, 4), stroke })
	box.Focused:Connect(function()
		stroke.Color = Theme.Accent
		stroke.Transparency = 0
		Input.SetFocus(box, true)
	end)
	box.FocusLost:Connect(function()
		stroke.Color = Theme.Stroke
		stroke.Transparency = 0.4
		Input.SetFocus(box, false)
	end)
	return box
end

-- -- Hit testing ---------------------------------------------------------------

function Widgets.Contains(Object: GuiObject, Point: Vector2): boolean
	local position, size = Object.AbsolutePosition, Object.AbsoluteSize
	return Point.X >= position.X and Point.Y >= position.Y
		and Point.X <= position.X + size.X and Point.Y <= position.Y + size.Y
end

--- The window drawn on top at `Point`, if any.
function Widgets.WindowAt(Point: Vector2): Window?
	local best: Window? = nil
	local bestZ = -math.huge
	for _, window in windows do
		local frame = window.Frame
		if frame.Visible and frame.ZIndex > bestZ and Widgets.Contains(frame, Point) then
			best, bestZ = window, frame.ZIndex
		end
	end
	return best
end

--- True when a press at `Point` belongs to the interface rather than to the stage.
function Widgets.OverUi(Point: Vector2): boolean
	return closePopup ~= nil or Widgets.WindowAt(Point) ~= nil
end

--- Whether two objects are drawn in the same ScreenGui or widget. A window can only cover
--- things in its own; the plugin has more than one widget, each with its own coordinates.
local function SameLayer(A: Instance, B: Instance): boolean
	return A:FindFirstAncestorWhichIsA("LayerCollector") == B:FindFirstAncestorWhichIsA("LayerCollector")
end

--- Connects a press on `Handle` that only fires when nothing else is covering it. Left
--- mouse and touch, plus the right button when `Secondary` is set.
function Widgets.Press(Handle: GuiObject, Callback: (Input: InputObject) -> (), Secondary: boolean?)
	Handle.InputBegan:Connect(function(input: InputObject)
		local secondary = input.UserInputType == Enum.UserInputType.MouseButton2
		if not Drag.IsPress(input) and not (Secondary and secondary) then
			return
		end
		if closePopup then
			return
		end
		local window = Widgets.WindowAt(Drag.Point(input))
		if window and SameLayer(window.Frame, Handle) and not Handle:IsDescendantOf(window.Frame) then
			return
		end
		Callback(input)
	end)
end

-- -- Windows -------------------------------------------------------------------

function Widgets.Setup(Panels: GuiBase2d, Popups: GuiBase2d)
	panelsGui = Panels
	popupsGui = Popups
end

local function Raise(Window: Window)
	topZ += 1
	Window.Frame.ZIndex = topZ
end

--- The size a window's frame should have right now. UIScale shrinks the Scale half of a
--- UDim2 along with everything else, so a window asked to be "full height" would come out
--- at Theme.Scale of the screen; dividing it back out keeps Scale meaning a fraction of the
--- screen while the Offsets still shrink with the text.
local function Fit(Window: Window): UDim2
	local size = Window.Size
	local scale = Theme.Scale
	if Window.Collapsed then
		return UDim2.new(size.X.Scale / scale, size.X.Offset, 0, HEADER_HEIGHT)
	end
	return UDim2.new(size.X.Scale / scale, size.X.Offset, size.Y.Scale / scale, size.Y.Offset)
end

--- Pulls a window back if it has been dragged, or the screen resized, far enough that it
--- could no longer be grabbed.
local function Keep(Window: Window)
	local frame = Window.Frame
	local bounds = panelsGui.AbsoluteSize
	local position = frame.AbsolutePosition - panelsGui.AbsolutePosition
	local size = frame.AbsoluteSize

	local dx, dy = 0, 0
	if position.X + size.X < KEEP_VISIBLE then
		dx = KEEP_VISIBLE - (position.X + size.X)
	elseif position.X > bounds.X - KEEP_VISIBLE then
		dx = bounds.X - KEEP_VISIBLE - position.X
	end
	if position.Y < 0 then
		dy = -position.Y
	elseif position.Y > bounds.Y - HEADER_HEIGHT then
		dy = bounds.Y - HEADER_HEIGHT - position.Y
	end

	if dx ~= 0 or dy ~= 0 then
		frame.Position += UDim2.fromOffset(dx, dy)
	end
end

function Widgets.Window(Title: string, Position: UDim2, Anchor: Vector2, Size: UDim2): Window
	topZ += 1
	local frame: Frame = Create("Frame", {
		Name = Title,
		AnchorPoint = Anchor,
		Position = Position,
		Size = Size,
		BackgroundColor3 = Theme.Window,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = topZ,
		Parent = panelsGui,
	}, { Corner(8), Outline() })
	local scale: UIScale = Create("UIScale", { Scale = Theme.Scale, Parent = frame })

	local header: Frame = Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
		Parent = frame,
	})
	local title = Widgets.Label({
		Text = Title,
		Font = Theme.FontBold,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -46, 1, 0),
		Parent = header,
	})
	local collapse = Widgets.Button("-", {
		Size = UDim2.fromOffset(22, 20),
		Position = UDim2.new(1, -28, 0, 5),
		BackgroundColor3 = Theme.Header,
		Parent = header,
	})
	Create("Frame", {
		Name = "Divider",
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = header,
	})

	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, HEADER_HEIGHT + 1),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 1)),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.TextFaint,
		Parent = frame,
	}, {
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Widgets.Padding(10, 14, 8, 10),
	})

	local window: Window = {
		Frame = frame,
		Body = body,
		Title = title,
		Scale = scale,
		Size = Size,
		Collapsed = false,
	}
	table.insert(windows, window)
	frame.Size = Fit(window)

	frame.InputBegan:Connect(function(input: InputObject)
		if Drag.IsPress(input) and Widgets.WindowAt(Drag.Point(input)) == window then
			Raise(window)
		end
	end)

	Widgets.Press(header, function(input)
		Raise(window)
		local start = frame.Position
		Drag.Follow(input, function(_, delta)
			frame.Position = start + UDim2.fromOffset(delta.X, delta.Y)
			Keep(window)
		end)
	end)

	collapse.Activated:Connect(function()
		window.Collapsed = not window.Collapsed
		body.Visible = not window.Collapsed
		collapse.Text = if window.Collapsed then "+" else "-"
		frame.Size = Fit(window)
		Keep(window)
	end)

	return window
end

function Widgets.Rescale(Scale: number)
	Theme.Scale = Scale
	for _, window in windows do
		window.Scale.Scale = Scale
		window.Frame.Size = Fit(window)
		Keep(window)
	end
end

-- -- Layout --------------------------------------------------------------------

--- A vertical list that grows with its content. Panels put their rows in one of these so
--- the whole lot can be hidden in one go when there is no origin selected.
function Widgets.Stack(Parent: Instance, Gap: number?): Frame
	return Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = Widgets.NextOrder(Parent),
		Parent = Parent,
	}, {
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, Gap or 4) }),
	})
end

function Widgets.Section(Parent: Instance, Text: string): TextLabel
	return Widgets.Label({
		Text = string.upper(Text),
		Font = Theme.FontBold,
		TextSize = Theme.SmallTextSize,
		TextColor3 = Theme.Accent,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = Widgets.NextOrder(Parent),
		Parent = Parent,
	})
end

function Widgets.Note(Parent: Instance, Text: string): TextLabel
	return Widgets.Label({
		Text = Text,
		TextSize = Theme.SmallTextSize,
		TextColor3 = Theme.TextFaint,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = Widgets.NextOrder(Parent),
		Parent = Parent,
	})
end

--- A labelled row. Returns the row, its label and the frame the field goes in. `Split` is
--- the fraction of the width the label gets.
function Widgets.Row(Parent: Instance, Text: string, Faint: boolean?, Split: number?): (Frame, TextLabel, Frame)
	local split = Split or 0.42
	local row: Frame = Create("Frame", {
		Name = Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, Theme.RowHeight),
		LayoutOrder = Widgets.NextOrder(Parent),
		Parent = Parent,
	})
	local label = Widgets.Label({
		Text = Text,
		TextColor3 = if Faint then Theme.TextFaint else Theme.TextDim,
		Size = UDim2.new(split, -6, 1, 0),
		Parent = row,
	})
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(split, 0),
		Size = UDim2.fromScale(1 - split, 1),
		Parent = row,
	})
	return row, label, content
end

-- -- Numbers -------------------------------------------------------------------

function Widgets.Format(Value: number, Options: NumberOptions?): string
	local options: NumberOptions = Options or {}
	if options.Integer then
		return tostring(math.round(Value))
	end
	local text = string.format(`%.{options.Decimals or 3}f`, Value)
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	if text == "-0" then
		text = "0"
	end
	return text
end

local function Constrain(Value: number, Options: NumberOptions): number
	if Options.Min then
		Value = math.max(Value, Options.Min)
	end
	if Options.Max then
		Value = math.min(Value, Options.Max)
	end
	if Options.Integer then
		Value = math.round(Value)
	end
	return Value
end

--- Lets `Grip` be dragged sideways to change a number, the way a label scrubs in Studio's
--- Properties panel. Holding Shift slows it down tenfold for fine tuning.
local function Scrub(Grip: GuiObject, Options: NumberOptions, Read: () -> number?, Write: (number) -> ())
	local step = Options.Step or 0.01
	local dragging = false

	Grip.MouseEnter:Connect(function()
		Input.SetCursor(SCRUB_CURSOR)
	end)
	Grip.MouseLeave:Connect(function()
		if not dragging then
			Input.SetCursor("")
		end
	end)

	Widgets.Press(Grip, function(input)
		-- Accumulated unrounded and unclamped-at-integers, so a slow drag on an integer
		-- field still gets there, and clamped at the ends so dragging back responds at once.
		local value = Read() or 0
		local lastX = input.Position.X
		dragging = true
		Drag.Follow(input, function(position)
			local fine = Input.IsKeyDown(Enum.KeyCode.LeftShift) or Input.IsKeyDown(Enum.KeyCode.RightShift)
			value += (position.X - lastX) * step * (if fine then 0.1 else 1)
			lastX = position.X
			if Options.Min then
				value = math.max(value, Options.Min)
			end
			if Options.Max then
				value = math.min(value, Options.Max)
			end
			Write(value)
		end, function()
			dragging = false
			Input.SetCursor("")
		end)
	end)
end

function Widgets.NumberField(Parent: GuiObject, Options: NumberOptions, Grip: GuiObject?, Size: UDim2?, Position: UDim2?): Field<number?>
	local box = Widgets.Box({
		Size = Size or UDim2.fromScale(1, 1),
		Position = Position or UDim2.new(),
		PlaceholderText = Options.Placeholder or "",
		Parent = Parent,
	})

	local current: number? = nil
	local field: Field<number?> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: number?)
		current = Value
		if not box:IsFocused() then
			box.Text = if Value then Widgets.Format(Value, Options) else ""
		end
	end

	local function Commit(Value: number?)
		field.Set(Value)
		if field.Changed then
			field.Changed(Value)
		end
	end

	box.FocusLost:Connect(function()
		local text = string.gsub(box.Text, "%s", "")
		if text == "" and Options.AllowEmpty then
			Commit(nil)
			return
		end
		local parsed = tonumber(text)
		if parsed then
			Commit(Constrain(parsed, Options))
		else
			field.Set(current)
		end
	end)

	if Grip then
		Scrub(Grip, Options, function()
			return current
		end, function(value)
			Commit(Constrain(value, Options))
		end)
	end

	return field
end

--- Several numbers side by side, each with a small caption that doubles as its scrub grip.
local function Split(Parent: GuiObject, Captions: { string }, Options: NumberOptions, CaptionWidth: number): { Field<number?> }
	local count = #Captions
	local fields = {}
	for index, caption in Captions do
		local cell: Frame = Create("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.new((index - 1) / count, if index > 1 then 2 else 0, 0, 0),
			Size = UDim2.new(1 / count, -2, 1, 0),
			Parent = Parent,
		})
		local grip = Widgets.Label({
			Text = caption,
			TextSize = Theme.SmallTextSize,
			TextColor3 = Theme.TextFaint,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(0, CaptionWidth, 1, 0),
			Parent = cell,
		})
		local field = Widgets.NumberField(cell, Options, grip, UDim2.new(1, -CaptionWidth, 1, 0), UDim2.fromOffset(CaptionWidth, 0))
		table.insert(fields, field)
	end
	return fields
end

function Widgets.RangeField(Parent: GuiObject, Options: NumberOptions): Field<NumberRange>
	local parts = Split(Parent, { "min", "max" }, Options, 26)
	local current = NumberRange.new(0)
	local field: Field<NumberRange> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: NumberRange)
		current = Value
		parts[1].Set(Value.Min)
		parts[2].Set(Value.Max)
	end

	-- NumberRange refuses Min > Max, so whichever end is being edited drags the other one
	-- along rather than the edit failing.
	local function Commit(Min: number, Max: number)
		local range = NumberRange.new(Min, Max)
		field.Set(range)
		if field.Changed then
			field.Changed(range)
		end
	end
	parts[1].Changed = function(value)
		local min = value or current.Min
		Commit(min, math.max(current.Max, min))
	end
	parts[2].Changed = function(value)
		local max = value or current.Max
		Commit(math.min(current.Min, max), max)
	end

	return field
end

function Widgets.Vector2Field(Parent: GuiObject, Options: NumberOptions, Captions: { string }?): Field<Vector2>
	local parts = Split(Parent, Captions or { "x", "y" }, Options, 14)
	local current = Vector2.zero
	local field: Field<Vector2> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: Vector2)
		current = Value
		parts[1].Set(Value.X)
		parts[2].Set(Value.Y)
	end

	local function Commit(Value: Vector2)
		field.Set(Value)
		if field.Changed then
			field.Changed(Value)
		end
	end
	parts[1].Changed = function(value)
		Commit(Vector2.new(value or current.X, current.Y))
	end
	parts[2].Changed = function(value)
		Commit(Vector2.new(current.X, value or current.Y))
	end

	return field
end

function Widgets.Vector3Field(Parent: GuiObject, Options: NumberOptions): Field<Vector3>
	local parts = Split(Parent, { "x", "y", "z" }, Options, 12)
	local current = Vector3.zero
	local field: Field<Vector3> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: Vector3)
		current = Value
		parts[1].Set(Value.X)
		parts[2].Set(Value.Y)
		parts[3].Set(Value.Z)
	end

	local function Commit(Value: Vector3)
		field.Set(Value)
		if field.Changed then
			field.Changed(Value)
		end
	end
	parts[1].Changed = function(value)
		Commit(Vector3.new(value or current.X, current.Y, current.Z))
	end
	parts[2].Changed = function(value)
		Commit(Vector3.new(current.X, value or current.Y, current.Z))
	end
	parts[3].Changed = function(value)
		Commit(Vector3.new(current.X, current.Y, value or current.Z))
	end

	return field
end

-- -- Other fields --------------------------------------------------------------

function Widgets.Toggle(Parent: GuiObject, OnText: string?, OffText: string?, Size: UDim2?): Field<boolean>
	local button = Widgets.Button("", {
		Size = Size or UDim2.new(0, 64, 1, 0),
		Parent = Parent,
	})
	local value = false
	local field: Field<boolean> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: boolean)
		value = Value
		button.Text = if Value then OnText or "On" else OffText or "Off"
		button.BackgroundColor3 = if Value then Theme.AccentDim else Theme.Button
		button.TextColor3 = if Value then Theme.Text else Theme.TextDim
	end

	button.Activated:Connect(function()
		field.Set(not value)
		if field.Changed then
			field.Changed(value)
		end
	end)

	field.Set(false)
	return field
end

function Widgets.TextField(Parent: GuiObject, Placeholder: string?, Size: UDim2?, Position: UDim2?): Field<string>
	local box = Widgets.Box({
		Size = Size or UDim2.fromScale(1, 1),
		Position = Position or UDim2.new(),
		PlaceholderText = Placeholder or "",
		Parent = Parent,
	})
	local field: Field<string> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: string)
		if not box:IsFocused() then
			box.Text = Value
		end
	end

	box.FocusLost:Connect(function()
		if field.Changed then
			field.Changed(box.Text)
		end
	end)

	return field
end

-- -- Popups --------------------------------------------------------------------

function Widgets.ClosePopup()
	local close = closePopup
	if close then
		close()
	end
end

--- Opens a list of choices under `Anchor`, or over it when there is no room below.
--- Clicking anywhere else closes it without choosing.
function Widgets.Popup(Anchor: GuiObject, Options: { string }, Current: string?, Pick: (Choice: string) -> ())
	Widgets.ClosePopup()

	local scale = Theme.Scale
	local blocker: TextButton = Create("TextButton", {
		Name = "Popup",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = popupsGui,
	})

	local width = math.max(Anchor.AbsoluteSize.X / scale, 120)
	local height = math.min(#Options * OPTION_HEIGHT + 8, POPUP_MAX_HEIGHT)
	local origin = Anchor.AbsolutePosition - popupsGui.AbsolutePosition
	local y = origin.Y + Anchor.AbsoluteSize.Y + 2
	if y + height * scale > popupsGui.AbsoluteSize.Y then
		y = math.max(0, origin.Y - 2 - height * scale)
	end

	local list: ScrollingFrame = Create("ScrollingFrame", {
		BackgroundColor3 = Theme.Header,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(origin.X, y),
		Size = UDim2.fromOffset(width, height),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.TextFaint,
		Parent = blocker,
	}, {
		Corner(6),
		Outline(),
		Create("UIScale", { Scale = scale }),
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		Widgets.Padding(4, 8, 4, 4),
	})

	local function Close()
		if closePopup == Close then
			closePopup = nil
		end
		blocker:Destroy()
	end
	closePopup = Close

	for index, option in Options do
		local button = Widgets.Button(option, {
			Size = UDim2.new(1, 0, 0, OPTION_HEIGHT - 2),
			LayoutOrder = index,
			Font = Theme.Font,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = if option == Current then Theme.AccentDim else Theme.Header,
			Parent = list,
		})
		Widgets.Padding(8).Parent = button
		button.Activated:Connect(function()
			Close()
			Pick(option)
		end)
	end

	blocker.Activated:Connect(Close)
end

function Widgets.Dropdown(Parent: GuiObject, Options: { string }, Size: UDim2?, Position: UDim2?): Field<string>
	local button = Widgets.Button("", {
		Size = Size or UDim2.fromScale(1, 1),
		Position = Position or UDim2.new(),
		Font = Theme.Font,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = Parent,
	})
	Widgets.Padding(8, 20).Parent = button
	Widgets.Label({
		Text = "v",
		TextSize = Theme.SmallTextSize,
		TextColor3 = Theme.TextDim,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 16, 0, 0),
		Size = UDim2.new(0, 14, 1, 0),
		Parent = button,
	})

	local value = ""
	local field: Field<string> = { Set = nil :: any, Changed = nil }

	function field.Set(Value: string)
		value = Value
		button.Text = Value
	end

	button.Activated:Connect(function()
		Widgets.Popup(button, Options, value, function(choice)
			field.Set(choice)
			if field.Changed then
				field.Changed(choice)
			end
		end)
	end)

	return field
end

-- -- Slider --------------------------------------------------------------------

export type Slider = {
	Bar: Frame,
	Gradient: UIGradient,
	Set: (Value: number) -> (),
	Changed: ((Value: number) -> ())?,
}

--- A 0..1 slider whose track is a gradient, for the colour picker's H, S and V.
function Widgets.Slider(Parent: GuiObject, Size: UDim2, Position: UDim2): Slider
	local bar: Frame = Create("Frame", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = Size,
		Position = Position,
		Parent = Parent,
	}, { Corner(4), Outline(Theme.Stroke, 0.3) })
	local gradient: UIGradient = Create("UIGradient", { Parent = bar })
	local knob: Frame = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 6, 1, 6),
		Position = UDim2.fromScale(0, 0.5),
		ZIndex = 2,
		Parent = bar,
	}, { Corner(3), Outline(Color3.new(0, 0, 0), 0.2) })

	local slider: Slider = { Bar = bar, Gradient = gradient, Set = nil :: any, Changed = nil }

	function slider.Set(Value: number)
		knob.Position = UDim2.fromScale(math.clamp(Value, 0, 1), 0.5)
	end

	Widgets.Press(bar, function(input)
		local function At(Point: Vector2)
			local value = math.clamp((Point.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			slider.Set(value)
			if slider.Changed then
				slider.Changed(value)
			end
		end
		At(Drag.Point(input))
		Drag.Follow(input, At)
	end)

	return slider
end

return Widgets

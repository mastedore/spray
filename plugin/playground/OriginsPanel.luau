--!strict
-->> OriginsPanel.luau
--> Creating, picking and deleting origins, plus the selected origin's name and size and a
--> couple of stage settings.
-->
--> Size is worth playing with: one stud is the origin's HEIGHT in pixels (with the default
--> SprayUnit), so resizing an origin rescales its whole effect without touching a single
--> emitter property.
-->
--> Inside the Studio plugin two more things show up, through the hooks in Host.luau: a
--> "From Studio selection" choice under + New, and an Export button that copies origins
--> out into the open place.

local RunService = game:GetService("RunService")

local Backdrop = require(script.Parent.Backdrop)
local Host = require(script.Parent.Host)
local Origin = require(script.Parent.Origin)
local Presets = require(script.Parent.Presets)
local Stage = require(script.Parent.Stage)
local Theme = require(script.Parent.Theme)
local Widgets = require(script.Parent.Widgets)

type Origin = Origin.Origin

type Entry = {
	Origin: Origin,
	Status: TextLabel,
}

const LIST_HEIGHT = 112
const ENTRY_HEIGHT = 24
const STATS_INTERVAL = 0.2

const FROM_SELECTION = "From Studio selection"
const EXPORT_CHOICES = { "Selected origin", "Selected origin + code", "All origins", "All origins + code" }

local OriginsPanel = {}

function OriginsPanel.Build()
	local window = Widgets.Window(
		"Origins",
		UDim2.new(1, -12, 1, -12),
		Vector2.new(1, 1),
		UDim2.new(0, 330, 0.45, -18)
	)
	local body = window.Body

	-- -- Actions ----------------------------------------------------------------

	local actions: Frame = Widgets.Create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = Widgets.NextOrder(body),
		Parent = body,
	})
	local create = Widgets.Button("+ New", {
		Size = UDim2.new(1 / 3, -4, 1, 0),
		BackgroundColor3 = Theme.AccentDim,
		Parent = actions,
	})
	local duplicate = Widgets.Button("Duplicate", {
		Position = UDim2.fromScale(1 / 3, 0),
		Size = UDim2.new(1 / 3, -4, 1, 0),
		Parent = actions,
	})
	local delete = Widgets.Button("Delete", {
		Position = UDim2.fromScale(2 / 3, 0),
		Size = UDim2.new(1 / 3, 0, 1, 0),
		BackgroundColor3 = Theme.DangerDim,
		Parent = actions,
	})

	create.Activated:Connect(function()
		local choices = Presets.Names
		local import = Host.Import
		if import then
			choices = table.clone(choices)
			table.insert(choices, 1, FROM_SELECTION)
		end
		Widgets.Popup(create, choices, nil, function(choice)
			if choice == FROM_SELECTION and import then
				local found = import()
				if #found == 0 then
					warn("[Spray] Select a ParticleEmitter in Explorer (or something with some inside) to bring it in.")
				end
				for _, entry in found do
					Stage.Add(entry.Emitter, entry.Name, nil, entry.Size)
				end
				return
			end
			Stage.Add(Presets.Build(choice), choice)
		end)
	end)
	duplicate.Activated:Connect(function()
		if Stage.Selected then
			Stage.Duplicate(Stage.Selected)
		end
	end)
	delete.Activated:Connect(function()
		if Stage.Selected then
			Stage.Remove(Stage.Selected)
		end
	end)

	local export = Host.Export
	if export then
		local button = Widgets.Button("Export to Studio", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = Theme.AccentDim,
			LayoutOrder = Widgets.NextOrder(body),
			Parent = body,
		})
		button.Activated:Connect(function()
			Widgets.Popup(button, EXPORT_CHOICES, nil, function(choice)
				local all = string.find(choice, "All", 1, true) ~= nil
				local snippet = string.find(choice, "code", 1, true) ~= nil
				local chosen: { Origin } = if all then table.clone(Stage.Origins)
					elseif Stage.Selected then { Stage.Selected }
					else {}
				if #chosen == 0 then
					warn("[Spray] There is no origin to export.")
					return
				end
				export(chosen, snippet)
			end)
		end)
	end

	-- -- List -------------------------------------------------------------------

	local list: ScrollingFrame = Widgets.Create("ScrollingFrame", {
		BackgroundColor3 = Theme.Field,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, LIST_HEIGHT),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.TextFaint,
		LayoutOrder = Widgets.NextOrder(body),
		Parent = body,
	}, {
		Widgets.Corner(5),
		Widgets.Outline(Theme.Stroke, 0.4),
		Widgets.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		Widgets.Padding(4, 8, 4, 4),
	})

	local entries: { Entry } = {}

	-- Listed in creation order, not draw order: the stage reorders its list every time
	-- something is selected, and a list that reshuffles under the cursor is unusable.
	local created: { Origin } = {}

	local function Rebuild()
		for _, child in list:GetChildren() do
			if child:IsA("TextButton") then
				child:Destroy()
			end
		end
		table.clear(entries)

		for index = #created, 1, -1 do
			if not table.find(Stage.Origins, created[index]) then
				table.remove(created, index)
			end
		end
		for _, origin in Stage.Origins do
			if not table.find(created, origin) then
				table.insert(created, origin)
			end
		end

		for index, origin in created do
			local selected = origin == Stage.Selected
			local button = Widgets.Button(origin.Name, {
				Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT - 2),
				LayoutOrder = index,
				Font = if selected then Theme.FontMedium else Theme.Font,
				TextXAlignment = Enum.TextXAlignment.Left,
				BackgroundColor3 = if selected then Theme.AccentDim else Theme.Field,
				Parent = list,
			})
			Widgets.Padding(8).Parent = button
			local status = Widgets.Label({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 110, 1, 0),
				TextSize = Theme.SmallTextSize,
				TextColor3 = Theme.TextDim,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = button,
			})
			button.Activated:Connect(function()
				Stage.Select(origin)
			end)
			table.insert(entries, { Origin = origin, Status = status })
		end
	end

	-- -- Selected ---------------------------------------------------------------

	local selectedStack = Widgets.Stack(body)
	Widgets.Section(selectedStack, "Selected origin")
	local _, _, nameContent = Widgets.Row(selectedStack, "Name")
	local nameField = Widgets.TextField(nameContent)
	local _, _, sizeContent = Widgets.Row(selectedStack, "Size (px)")
	local sizeField = Widgets.Vector2Field(sizeContent, { Integer = true, Min = 4, Max = 2000, Step = 1 }, { "w", "h" })
	local _, _, liveContent = Widgets.Row(selectedStack, "Live particles")
	local live = Widgets.Label({ Size = UDim2.fromScale(1, 1), TextColor3 = Theme.Text, Parent = liveContent })

	nameField.Changed = function(text)
		if Stage.Selected then
			Stage.Rename(Stage.Selected, text)
			nameField.Set(Stage.Selected.Name)
		end
	end
	sizeField.Changed = function(value)
		if Stage.Selected then
			Stage.Selected:Resize(value)
		end
	end

	-- -- Stage ------------------------------------------------------------------

	local stageStack = Widgets.Stack(body)
	Widgets.Section(stageStack, "Stage")
	local _, _, backdropContent = Widgets.Row(stageStack, "Backdrop")
	local backdrop = Widgets.Dropdown(backdropContent, Backdrop.Options)
	backdrop.Set(Backdrop.Current)
	backdrop.Changed = Backdrop.Set
	local _, _, outlineContent = Widgets.Row(stageStack, "Origin outlines")
	local outlines = Widgets.Toggle(outlineContent)
	outlines.Set(Stage.Outlines)
	outlines.Changed = Stage.SetOutlines
	Widgets.Note(stageStack, "Drag an origin to move it, click it to edit it. Every origin keeps playing when you select another.")

	-- -- Binding ----------------------------------------------------------------

	local function Bind()
		local origin = Stage.Selected
		selectedStack.Visible = origin ~= nil
		duplicate.TextTransparency = if origin then 0 else 0.6
		delete.TextTransparency = if origin then 0 else 0.6
		if origin then
			nameField.Set(origin.Name)
			local size = origin.Frame.Size
			sizeField.Set(Vector2.new(size.X.Offset, size.Y.Offset))
		end
		Rebuild()
	end

	Stage.SelectionChanged:Connect(Bind)
	Stage.ListChanged:Connect(Bind)
	Bind()

	local elapsed = 0
	RunService.Heartbeat:Connect(function(delta: number)
		elapsed += delta
		if elapsed < STATS_INTERVAL then
			return
		end
		elapsed = 0

		for _, entry in entries do
			local origin = entry.Origin
			if origin.Destroyed then
				continue
			end
			local state = if origin.Playing then "playing" else "paused"
			entry.Status.Text = if origin.Loop then `{state} · loop` else state
		end

		local origin = Stage.Selected
		if origin then
			local maximum = origin.Emitter:GetAttribute("SprayMaxParticles")
			live.Text = `{origin:LiveCount()} / {if typeof(maximum) == "number" then maximum else 400}`
		end
	end)
end

return OriginsPanel

--!strict
-->> PreviewMode.luau
--> Plays the ParticleEmitters selected in Studio right where they are, under the
--> playground's own Playback window in a dock widget of its own. Several emitters play as
--> one effect, on one timeline (Group.luau).
-->
--> It follows edits. Change any property or Spray attribute of a previewed emitter in the
--> Properties panel, playing or paused, and it rebuilds on the spot without losing its
--> place in the run, the same way the playground does for its own panels.
-->
--> Previewing has to touch the place. Each Spray draws its pool of ImageLabels into the
--> emitter's own GuiObject, and hidden UI above an emitter is shown, or there would be
--> nothing to look at. The pools are never saved (they aren't Archivable), and everything
--> that was shown is hidden again on Stop, which also runs when the plugin unloads.

local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Gather = require(script.Parent.Gather)
local Group = require(script.Parent.Group)
local Input = require(script.Parent.playground.Input)
local Origin = require(script.Parent.playground.Origin)
local PlaybackPanel = require(script.Parent.playground.PlaybackPanel)
local Theme = require(script.Parent.playground.Theme)
local Widgets = require(script.Parent.playground.Widgets)

type Group = Group.Group

const WIDGET_ID = "SprayPreview"
const TITLE = "Spray Preview"

type Restore = {
	Object: Instance,
	Property: string,
	Value: any,
}

local PreviewMode = {}

local widget: DockWidgetPluginGui = nil :: any
local note: TextLabel = nil :: any
local changed: (Active: boolean) -> () = function() end

local group: Group? = nil
local restores: { Restore } = {}
local connections: { RBXScriptConnection } = {}

-- -- Showing what the emitter needs ----------------------------------------------

--- Sets a property and remembers the old value for Stop.
local function Force(Object: Instance, Property: string, Value: any)
	local current = (Object :: any)[Property]
	if current == Value then
		return
	end
	table.insert(restores, { Object = Object, Property = Property, Value = current })
	;(Object :: any)[Property] = Value
end

--- Turns on whatever above the emitter would keep it off screen.
local function Reveal(Emitter: ParticleEmitter)
	if Emitter:IsDescendantOf(StarterGui) then
		Force(StarterGui, "ShowDevelopmentGui", true)
	end
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

local function Restore()
	for index = #restores, 1, -1 do
		local restore = restores[index]
		if restore.Object.Parent then
			pcall(function()
				(restore.Object :: any)[restore.Property] = restore.Value
			end)
		end
	end
	table.clear(restores)
end

-- -- Lifecycle -----------------------------------------------------------------

function PreviewMode.Active(): boolean
	return group ~= nil
end

function PreviewMode.Stop()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)

	local current = group
	group = nil
	if current then
		current:Destroy()
	end
	Restore()

	if widget and widget.Enabled then
		widget.Enabled = false
	end
	changed(false)
end

--- Starts previewing the selection. Returns whether it did, and what to tell the user.
function PreviewMode.Start(): (boolean, string)
	PreviewMode.Stop()

	local emitters = Gather.Selected()
	if #emitters == 0 then
		return false, "Select a ParticleEmitter in Explorer (or a Frame or ScreenGui with some inside) to preview it."
	end

	local members: { Origin.Origin } = {}
	local skipped: { string } = {}
	for _, emitter in emitters do
		-- Spray draws inside a GuiObject; one on a Part or an Attachment has nowhere to go.
		if not emitter:FindFirstAncestorWhichIsA("GuiObject") then
			table.insert(skipped, emitter.Name)
			continue
		end
		Reveal(emitter)
		local ok, result = pcall(Origin.Wrap, emitter, emitter.Name)
		if ok then
			table.insert(members, result)
		else
			warn(`[Spray] Couldn't preview {emitter:GetFullName()}: {result}`)
		end
	end

	if #members == 0 then
		Restore()
		return false, "None of the selected emitters are inside a GuiObject, so there is nowhere to draw them."
	end

	local current = Group.New(members)
	group = current

	-- An emitter deleted or dragged out of the UI mid-preview just leaves it.
	for _, member in members do
		local emitter = member.Emitter
		table.insert(connections, emitter.AncestryChanged:Connect(function()
			if emitter:IsDescendantOf(game) and emitter:FindFirstAncestorWhichIsA("GuiObject") then
				return
			end
			current:Drop(member)
			if #current.Members == 0 then
				PreviewMode.Stop()
			end
		end))
	end
	table.insert(connections, RunService.Heartbeat:Connect(function()
		current:Update(os.clock())
	end))

	local count = #members
	local message = `Previewing {count} emitter{if count == 1 then "" else "s"}. Edit them in Properties and the preview follows.`
	if #skipped > 0 then
		message ..= ` Skipped {#skipped} not inside a GuiObject: {table.concat(skipped, ", ")}.`
	end
	note.Text = message

	widget.Enabled = true
	changed(true)
	return true, message
end

-- -- Widget --------------------------------------------------------------------

function PreviewMode.Setup(Plugin: Plugin, Changed: (Active: boolean) -> ())
	changed = Changed

	-- Never restored open: a preview is of whatever was selected at the time, and there is
	-- nothing to show in one Studio brings back by itself.
	local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 640, 176, 520, 150)
	widget = Plugin:CreateDockWidgetPluginGuiAsync(WIDGET_ID, info)
	widget.Name = WIDGET_ID
	widget.Title = TITLE
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local surface = Widgets.Create("Frame", {
		Name = "Surface",
		BackgroundColor3 = Theme.Window,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = widget,
	})
	local body: Frame = Widgets.Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = surface,
	}, {
		Widgets.Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Widgets.Padding(10, 14, 8, 10),
	})

	local mouse = Plugin:GetMouse()
	Input.UseWidget(widget, surface, function(Icon)
		mouse.Icon = Icon
	end)

	PlaybackPanel.Build({
		Target = function()
			return group :: any
		end,
		Parent = body :: GuiObject,
		Title = function(Text)
			widget.Title = `Spray {Text}`
		end,
	})
	note = Widgets.Note(body, "")

	-- Closing the widget is the other way to stop.
	widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not widget.Enabled and group then
			PreviewMode.Stop()
		end
	end)
end

return PreviewMode

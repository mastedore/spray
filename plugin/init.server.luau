--!strict
-->> Spray plugin
--> Spray inside Roblox Studio. One toolbar, four buttons:
-->
-->   Import      installs the latest Spray at ReplicatedStorage.Packages.Spray, replacing
-->               the version there if there is one (Installer.luau)
-->   Remove      takes it out again
-->   Playground  opens the playground in a dock widget: the same one the playground game
-->               runs, plus a way in (+ New > From Studio selection) and a way out (Export
-->               to Studio, with or without the code that plays it)
-->   Preview     plays the ParticleEmitters selected in Studio where they are, under the
-->               playground's Playback window, following every edit live
-->
--> The playground lives in ./playground and is the SAME folder the playground game is
--> built from, so a change there reaches both. The plugin brings its own copy of Spray
--> (./Spray in the build) for the playground and the preview to draw with, so neither
--> depends on what the open place has installed.
-->
--> Build it into Studio's plugins folder with:
-->
-->     rojo build plugin.project.json --plugin SprayPlugin.rbxm
-->
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local RunService = game:GetService("RunService")

-- Plugins also load into every playtest; none of this means anything there.
if not RunService:IsEdit() then
	return
end

local Exporter = require(script.Exporter)
local Host = require(script.playground.Host)
local Installer = require(script.Installer)
local PlaygroundWidget = require(script.PlaygroundWidget)
local PreviewMode = require(script.PreviewMode)

--- Toolbar icons. Empty shows the button's text alone; put asset ids here to give them one.
const ICONS = {
	Import = "",
	Remove = "",
	Playground = "",
	Preview = "",
}

Host.Spray = require(script.Spray) :: any
Host.Export = function(Origins, WithSnippet)
	Exporter.Export(plugin, Origins, WithSnippet)
end

local toolbar = plugin:CreateToolbar("Spray")

local function Button(Id: string, Tooltip: string, Icon: string, Text: string): PluginToolbarButton
	local button = toolbar:CreateButton(Id, Tooltip, Icon, Text)
	button.ClickableWhenViewportHidden = true
	return button
end

local importButton = Button(
	"SprayImport",
	"Install the latest Spray at ReplicatedStorage.Packages.Spray, replacing the one there",
	ICONS.Import,
	"Import"
)
local removeButton = Button("SprayRemove", "Remove ReplicatedStorage.Packages.Spray", ICONS.Remove, "Remove")
local playgroundButton = Button(
	"SprayPlayground",
	"Open or close the Spray playground",
	ICONS.Playground,
	"Playground"
)
local previewButton = Button(
	"SprayPreview",
	"Play the ParticleEmitters selected in Explorer, with a timeline. Click again to stop",
	ICONS.Preview,
	"Preview"
)

-- -- Import / Remove ---------------------------------------------------------------

local installing = false

importButton.Click:Connect(function()
	importButton:SetActive(false)
	if installing then
		return
	end
	installing = true
	print("[Spray] Installing...")
	local ok, message = pcall(Installer.Install, script.Spray)
	installing = false
	if ok then
		print(`[Spray] {message}`)
	else
		warn(`[Spray] Install failed: {message}`)
	end
end)

removeButton.Click:Connect(function()
	removeButton:SetActive(false)
	print(`[Spray] {Installer.Remove()}`)
end)

-- -- Playground ------------------------------------------------------------------

PlaygroundWidget.Setup(plugin, function(Open)
	playgroundButton:SetActive(Open)
end)
playgroundButton:SetActive(PlaygroundWidget.IsOpen())

playgroundButton.Click:Connect(function()
	PlaygroundWidget.Toggle()
	playgroundButton:SetActive(PlaygroundWidget.IsOpen())
end)

-- -- Preview ---------------------------------------------------------------------

PreviewMode.Setup(plugin, function(Active)
	previewButton:SetActive(Active)
end)

previewButton.Click:Connect(function()
	if PreviewMode.Active() then
		PreviewMode.Stop()
		return
	end
	local ok, message = PreviewMode.Start()
	if ok then
		print(`[Spray] {message}`)
	else
		warn(`[Spray] {message}`)
	end
	previewButton:SetActive(PreviewMode.Active())
end)

-- Whatever the preview showed gets hidden again, and its pools go, before the plugin does.
plugin.Unloading:Connect(PreviewMode.Stop)

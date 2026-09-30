--!strict
-->> Playground (game entry)
--> The Spray playground: a place anyone can join to try Spray without installing it.
-->
--> Everything happens on the client. The stage holds any number of ORIGINS - draggable
--> frames, each with a ParticleEmitter inside drawn by its own Spray - and four windows edit
--> the selected one: its emitter properties, its Spray attributes, its playback, and the
--> list of origins itself.
-->
--> The same modules also run inside the Studio plugin (plugin/init.server.luau), which is
--> why this script only does the game-specific part: where the layers go, which Spray to
--> use, and where input comes from. App.luau does the rest.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local App = require(script.Parent.App)
local Host = require(script.Parent.Host)
local Input = require(script.Parent.Input)
local Widgets = require(script.Parent.Widgets)

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

local function Layer(Name: string, DisplayOrder: number, IgnoreInset: boolean): ScreenGui
	return Widgets.Create("ScreenGui", {
		Name = Name,
		DisplayOrder = DisplayOrder,
		IgnoreGuiInset = IgnoreInset,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
end

Host.Spray = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Spray")) :: any
Input.UseUserInputService()

local camera = Workspace.CurrentCamera
App.Start({
	Backdrop = Layer("SprayBackdrop", -10, true),
	Stage = Layer("SprayStage", 0, false),
	Panels = Layer("SprayPanels", 10, false),
	Popups = Layer("SprayPopups", 20, false),
}, function()
	return camera.ViewportSize
end, camera:GetPropertyChangedSignal("ViewportSize"))

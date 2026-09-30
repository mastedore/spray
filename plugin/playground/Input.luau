--!strict
-->> Input.luau
--> Where the pointer and the keyboard come from. Everything in the playground that needs
--> more than a GuiObject's own events (dragging, picking origins off the stage, the Space
--> shortcut, Shift for fine scrubbing) listens here instead of to UserInputService.
-->
--> In the game this is just UserInputService passed through. The Studio plugin can't do
--> that: UserInputService only hears the game window, never a dock widget. So the plugin
--> hands over the widget instead, and input is read from a transparent frame covering it,
--> which GuiObject events do reach, plus the widget's own idea of where the mouse is.
-->
--> Moved and Ended are shaped around what dragging needs rather than mirroring
--> UserInputService: Moved gives a position (a widget has no InputObject to give while
--> the pointer is outside it), and Ended can fire with nil, meaning "whatever was held,
--> consider it let go".

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Signal = require(script.Parent.Signal)

const MOUSE_BUTTONS: { [Enum.UserInputType]: boolean } = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true,
}

local Input = {
	--- (Input: InputObject, Processed: boolean, Root: Instance?). Root is the widget the
	--- press happened in, or nil in the game, where there is only one screen.
	Began = Signal.New(),
	--- (Position: Vector2, Touch: InputObject?). Touch is the InputObject of the finger that
	--- moved, nil for the mouse.
	Moved = Signal.New(),
	--- (Input: InputObject?). nil drops every press at once.
	Ended = Signal.New(),
}

local keyDown: (Enum.KeyCode) -> boolean = function()
	return false
end
local setCursor: (string) -> () = function() end
local focused: TextBox? = nil

function Input.IsKeyDown(Key: Enum.KeyCode): boolean
	return keyDown(Key)
end

function Input.SetCursor(Icon: string)
	setCursor(Icon)
end

--- Called by every playground TextBox as it gains and loses focus, so shortcuts can stand
--- aside while someone types. Tracked here because GetFocusedTextBox can't see a widget.
function Input.SetFocus(Box: TextBox, Focused: boolean)
	if Focused then
		focused = Box
	elseif focused == Box then
		focused = nil
	end
end

function Input.Typing(): boolean
	return focused ~= nil
end

--- The in-game source.
function Input.UseUserInputService()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		Input.Began:Fire(input, processed, nil)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement then
			Input.Moved:Fire(Vector2.new(input.Position.X, input.Position.Y), nil)
		elseif kind == Enum.UserInputType.Touch then
			Input.Moved:Fire(Vector2.new(input.Position.X, input.Position.Y), input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		Input.Ended:Fire(input)
	end)
	keyDown = function(Key)
		return UserInputService:IsKeyDown(Key)
	end
	setCursor = function(Icon)
		UserInputService.MouseIcon = Icon
	end
end

--- A Studio dock widget as a source. Can be called for several widgets; each press says
--- which one it came from, and a press in one never moves anything in another, because a
--- widget only tracks the mouse while it is over it or holding a press that began on it.
---
--- `Surface` has to cover the whole widget and hold everything else in it. GuiObject input
--- events reach every object under the pointer, not just the topmost, so as the ancestor
--- of whatever gets pressed it hears all of them. `Cursor` sets the mouse icon (a
--- PluginMouse's, in practice); widgets have no MouseIcon of their own.
function Input.UseWidget(Widget: PluginGui, Surface: GuiObject, Cursor: ((string) -> ())?)
	local keys: { [Enum.KeyCode]: boolean } = {}
	local last: Vector2? = nil
	local held = false

	Surface.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			keys[input.KeyCode] = true
		elseif MOUSE_BUTTONS[kind] then
			held = true
		end
		Input.Began:Fire(input, Input.Typing(), Widget)
	end)

	Surface.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			keys[input.KeyCode] = nil
		elseif MOUSE_BUTTONS[kind] then
			held = false
		end
		Input.Ended:Fire(input)
	end)

	-- The pointer is polled rather than taken from InputChanged, because the widget keeps
	-- reporting it while a press that began inside is dragged out, and InputChanged doesn't.
	RunService.Heartbeat:Connect(function()
		if not Widget.Enabled then
			return
		end
		local position = Widget:GetRelativeMousePosition()
		if position == last then
			return
		end
		last = position

		local size = Widget.AbsoluteSize
		local outside = position.X < 0 or position.Y < 0 or position.X > size.X or position.Y > size.Y
		if outside then
			-- A button let go out here never reaches the widget, and a drag that missed its
			-- release would stay glued to the pointer. Ending it at the edge is the lesser evil.
			if held then
				held = false
				Input.Ended:Fire(nil)
			end
			return
		end
		Input.Moved:Fire(position, nil)
	end)

	-- Focus moving to another window means whatever was held got released over there.
	Widget.WindowFocusReleased:Connect(function()
		table.clear(keys)
		held = false
		Input.Ended:Fire(nil)
	end)

	keyDown = function(Key)
		return keys[Key] == true
	end
	if Cursor then
		setCursor = Cursor
	end
end

--- True when `Object` belongs to the place `Root` names: anywhere at all when there is no
--- root (the game), otherwise inside that widget.
function Input.Within(Root: Instance?, Object: Instance): boolean
	return Root == nil or Object:IsDescendantOf(Root)
end

return Input

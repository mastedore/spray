--!strict
-->> Drag.luau
--> Follows a press around the screen until it is released. Windows, origins, the timeline,
--> sliders and sequence keypoints all drag through this one function, so mouse and touch
--> behave the same everywhere, and so does the game against a Studio widget (Input.luau
--> hides the difference).
-->
--> Positions come from InputObject.Position, which is in the same space as every
--> GuiObject's AbsolutePosition. Comparing the two directly is therefore safe; converting
--> through the mouse location is not, because that one includes the top bar inset.

local Input = require(script.Parent.Input)

local Drag = {}

--- Left mouse button or a finger. The two kinds of input that can start a drag.
function Drag.IsPress(Press: InputObject): boolean
	local kind = Press.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

function Drag.Point(Press: InputObject): Vector2
	return Vector2.new(Press.Position.X, Press.Position.Y)
end

--- Calls `Moved` with the pointer position, and its offset from where the press began,
--- every time the pointer moves, until the press that `Press` started is released.
function Drag.Follow(Press: InputObject, Moved: (Position: Vector2, Delta: Vector2) -> (), Ended: (() -> ())?)
	local start = Drag.Point(Press)
	local touch = Press.UserInputType == Enum.UserInputType.Touch
	local button = Press.UserInputType

	local stopMoving: () -> ()
	local stopEnding: () -> ()

	-- A touch keeps reporting through the same InputObject for its whole life; the mouse
	-- reports its moves without one.
	stopMoving = Input.Moved:Connect(function(position: Vector2, finger: InputObject?)
		if (touch and finger == Press) or (not touch and finger == nil) then
			Moved(position, position - start)
		end
	end)

	stopEnding = Input.Ended:Connect(function(finish: InputObject?)
		local released = finish == nil
			or (touch and finish == Press)
			or (not touch and finish.UserInputType == button)
		if released then
			stopMoving()
			stopEnding()
			if Ended then
				Ended()
			end
		end
	end)
end

return Drag

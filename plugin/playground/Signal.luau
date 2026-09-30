--!strict
-->> Signal.luau
--> The smallest observer that does the job: a list of callbacks. The playground only ever
--> needs "tell whoever is listening that this changed", within one LocalScript, so there is
--> nothing a BindableEvent would add except copying every table that goes through it.

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: {
	_callbacks: { (...any) -> () },
}, Signal))

function Signal.New(): Signal
	return setmetatable({ _callbacks = {} }, Signal)
end

--- Returns a function that disconnects the callback again.
function Signal.Connect(self: Signal, Callback: (...any) -> ()): () -> ()
	table.insert(self._callbacks, Callback)
	return function()
		local index = table.find(self._callbacks, Callback)
		if index then
			table.remove(self._callbacks, index)
		end
	end
end

function Signal.Fire(self: Signal, ...: any)
	-- Cloned so a listener that disconnects itself does not skip the one after it.
	for _, callback in table.clone(self._callbacks) do
		callback(...)
	end
end

return Signal

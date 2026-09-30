--!strict
-->> Gather.luau
--> Every ParticleEmitter at or under what's selected in Studio, each once, in the order it
--> was selected. Selecting a whole ScreenGui (or anything else) and getting every emitter
--> inside is what makes a layered effect one click to preview.

local Selection = game:GetService("Selection")

local Gather = {}

function Gather.Selected(): { ParticleEmitter }
	local found: { ParticleEmitter } = {}
	local seen: { [ParticleEmitter]: boolean } = {}

	local function Add(Node: Instance)
		if Node:IsA("ParticleEmitter") and not seen[Node] then
			seen[Node] = true
			table.insert(found, Node)
		end
	end

	for _, root in Selection:Get() do
		Add(root)
		for _, node in root:GetDescendants() do
			Add(node)
		end
	end
	return found
end

return Gather

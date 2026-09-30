--!strict
-->> Host.luau
--> What the playground gets from wherever it is running. The game and the Studio plugin
--> each fill this in before starting it (App.luau), which is what lets both run the very
--> same modules.
-->
--> Spray is handed over rather than required here because each host keeps its own copy:
--> the game uses ReplicatedStorage.Packages.Spray like any other consumer would, while
--> the plugin carries one inside itself so it works in a place that hasn't installed it.
-->
--> The hooks are plugin only. Whatever needs one checks that it's there, and the game,
--> which leaves them nil, simply never shows the controls that would use them.

--- The part of a Spray the playground uses.
export type Effect = {
	Emit: (self: any, Count: number) -> (),
	Pause: (self: any) -> (),
	Resume: (self: any) -> (),
	Forward: (self: any, DeltaTime: number) -> (),
	SetTime: (self: any, Time: number) -> (),
	UseRandom: (self: any, Use: boolean?) -> (),
	RandomSeed: (self: any, Seed: number) -> (),
	Cleanup: (self: any) -> (),
	Destroy: (self: any) -> (),
}

export type Library = {
	New: (Target: ParticleEmitter) -> Effect,
}

--- An emitter brought into the playground from outside, with the size of the GuiObject it
--- was drawn in, when there was one.
export type Imported = {
	Emitter: ParticleEmitter,
	Name: string,
	Size: Vector2?,
}

local Host = {
	Spray = nil :: Library?,

	--- Copies origins out into the open place. Takes the origins and whether to write the
	--- code that plays them.
	Export = nil :: ((Origins: { any }, Snippet: boolean) -> ())?,

	--- Emitters to add to the stage, taken from whatever is selected in Studio.
	Import = nil :: (() -> { Imported })?,
}

function Host.Library(): Library
	return assert(Host.Spray, "Playground: Host.Spray has to be set before the playground starts")
end

return Host

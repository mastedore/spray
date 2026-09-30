-->> RunTests.server.luau
--> Runs every .spec module under ReplicatedStorage.Tests with TestEZ and prints the
--> report to the output. Serve test.project.json, press Run (F8), read the output.
-->> Spray is licensed under the Mozilla Public License 2.0. See LICENSE.md.
---- Copyright (C) 2026 Mastedore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage:WaitForChild("DevPackages"):WaitForChild("TestEZ"))

local results = TestEZ.TestBootstrap:run({ ReplicatedStorage:WaitForChild("Tests") })

if results.failureCount > 0 or #results.errors > 0 then
	error(`Spray tests: {results.failureCount} failed, {#results.errors} errored`, 0)
end
print(`Spray tests: all {results.successCount} passed`)

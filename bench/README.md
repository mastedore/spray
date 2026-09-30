# Benchmark

`Benchmark.client.luau` runs the same burst effect in Spray and in Emitter2D and times both. It isn't part of the package, and Wally leaves this folder out.

## Running it

You need a place with Spray at `ReplicatedStorage.Packages.Spray` and Emitter2D's client under `StarterPlayerScripts` (the playground place has both). Start a playtest, put the script in `StarterPlayerScripts` or parent a copy under `PlayerGui`, and read the output. It prints one line per test and a JSON dump at the end, and takes about four minutes.

## What it measures

- **steady**: 100 to 4000 particles alive across 10 emitters, with each library's per-frame update timed on its own. Nothing spawns or dies while it's measured, so this is the plain cost of keeping particles on screen. It runs twice: with the full effect, where every drawn property changes on every frame, and with a simple one (flat colour, no spin) that looks more like a typical UI effect.
- **burst**: getting a 200-particle burst on screen, cold (no ImageLabels exist yet) and warm (reusing the previous burst's). Spray also runs it on a pool built beforehand with `:Prewarm()`.
- **live**: both libraries on their own schedulers, re-bursting every 0.25 s, with frame times, the library's CPU time per frame and the average number of particles alive. They take turns three times each, alternating who goes first, and each reports its median round.

The two effects are matched by hand: same texture, spread, speed, size and transparency curves, colour gradient, rotation, gravity and drag, and the same size on screen.

## Reading the numbers

Compare numbers from the same run. Absolute times move a lot between runs and machines (the live test especially, since a slow frame spawns more per frame and the garbage collector works harder), while the ratio between the two libraries stays put.

Emitter2D is compiled with `--!native` and Spray isn't, so these numbers are native Emitter2D against interpreted Spray.

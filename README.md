<p align="center">
  <img src="https://github.com/mastedore/spray/blob/main/resources/spray_logo.png" alt="Spray logo"/>
</p>
<h1 align="center">Spray!</h1>

Documentation and API reference: [mastedore.github.io/spray](https://mastedore.github.io/spray/)

<!--moonwave-hide-before-this-line-->

ParticleEmitters for Roblox GUI. Put a regular ParticleEmitter inside a Frame, author it in the Properties panel the way you would in 3D, and Spray plays it on screen in 2D with ImageLabels.

```lua
local Spray = require(ReplicatedStorage.Packages.Spray)

local sparkles = Spray.New(button.Sparkles) -- a ParticleEmitter inside a GuiObject
sparkles:Emit(30)
```

The emitter is the config. Texture, Color, Size, Transparency, Squash, Speed, Drag, Acceleration, shapes, flipbooks, Rate and TimeScale are read from it directly. The few settings a 3D emitter has no property for (the emission area on screen, a size multiplier, the particle cap) are attributes on that same emitter.

Particles aren't stepped frame by frame. Where each one is gets computed from the Spray's clock, so an effect can be paused, jumped to any moment with `:SetTime()` or played backwards, and with a fixed seed it produces the same particles every time.

## Installing

With [Wally](https://wally.run):

```toml
[dependencies]
Spray = "mastedore/spray@1.0.0"
```

With the [Studio plugin](https://github.com/mastedore/spray/blob/main/plugin/README.md), press **Import** on the Spray toolbar. It puts the latest version from this repository at `ReplicatedStorage.Packages.Spray`.

Or build the model yourself with `rojo build default.project.json -o Spray.rbxm` and drop it wherever you keep your packages.

Spray draws on the client, so require it from a LocalScript.

## Usage

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spray = require(ReplicatedStorage.Packages.Spray)

local button = script.Parent -- a TextButton with a ParticleEmitter named Confetti inside
local confetti = Spray.New(button.Confetti)

button.Activated:Connect(function()
	confetti:Emit(40)
end)
```

A new Spray starts paused. Calling `:Emit()` on a paused Spray rewinds it to zero and plays from the start, and on one that's already playing it adds another burst on top, the same as `ParticleEmitter:Emit()`. An emitter with `Enabled` on and a `Rate` above zero also streams particles for as long as the Spray is playing, so `:Resume()` is enough to start it.

Spray reads the emitter once. If you change its properties while the game runs, call `:Cleanup()` and the next use reads them again.

To freeze or replay an exact moment:

```lua
local explosion = Spray.New(frame.Explosion)
explosion:UseRandom(false)
explosion:RandomSeed(7)   -- same seed, same particles, down to the flipbook frame

explosion:Emit(60)
explosion:Pause()
explosion:SetTime(0.35)   -- exactly what you'd see 0.35 s into the effect
explosion:Forward(-0.1)   -- back to 0.25 s
```

### API

The [API reference](https://mastedore.github.io/spray/api/Spray) explains each of these in more detail, with examples.

| Call | What it does |
| --- | --- |
| `Spray.New(emitter)` | Wraps a ParticleEmitter that has a GuiObject above it (a Folder in between is fine) and builds its pool. Starts paused at time 0. |
| `:Emit(count)` | Releases `count` particles, capped at `SprayMaxParticles`. Rewinds and plays if the Spray was paused, stacks on top if it was playing. |
| `:Pause()` | Stops the clock. Particles freeze where they are. |
| `:Resume()` | Starts the clock again from where it stopped. |
| `:Forward(seconds)` | Moves the clock by that many seconds (negative rewinds) and redraws. Doesn't change whether the Spray is playing. |
| `:SetTime(seconds)` | Jumps the clock to a time and redraws. Doesn't change whether the Spray is playing either. |
| `:UseRandom(use)` | `true` (the default) rolls a new seed every time the effect restarts. `false` replays the seed from `:RandomSeed()`. |
| `:RandomSeed(seed)` | Sets the seed used while `:UseRandom(false)` is on. |
| `:Prewarm(count)` | Builds `count` ImageLabels now (all of `SprayMaxParticles` if left out), so later bursts reuse them instead of creating any. Call it where a hitch doesn't matter, like a loading screen. |
| `:Cleanup()` | Throws away the pool and the snapshot of the emitter. The next call rebuilds both and reads the emitter again. |
| `:Destroy()` | Cleans up for good. Using the object afterwards throws an error. |

## Attributes

All optional, all set on the ParticleEmitter.

| Attribute | Type | Default | What it does |
| --- | --- | --- | --- |
| `SprayScale` | number | `1` | Multiplies size and speed together. It rescales the whole effect without changing its shape, so try this one first. |
| `SpraySizeScale` | number | `1` | Size only, on top of `SprayScale`. |
| `SpraySpeedScale` | number | `1` | Speed only, on top of `SprayScale`. |
| `SprayUnit` | string | `RelativeYY` | Which edge of the parent counts as one stud: `RelativeYY`, `RelativeXX`, `RelativeMin`, `RelativeMax`, or `Offset` (1 stud = 1 pixel). |
| `SprayEmissionSize` | Vector2 | `0, 0` | Emission area as a fraction of the parent's size. Zero is a point emitter. |
| `SprayMaxParticles` | number | `400` | Most particles alive at once. `:Emit()` is capped to it, and the stream's rate is lowered to fit it. |
| `SprayGlowLayers` | number | `1` | Copies drawn per particle, from 1 to 8. The extra copies are the halo that stands in for LightEmission. |
| `SprayZIndex` | number | parent's ZIndex | Base ZIndex that `ZOffset` is added to. |
| `SprayFlipbookGrid` | number | `4` | Frames per row, for `FlipbookLayout = Custom`. |
| `SprayFlipbookResolution` | number | `1024` | Size of the flipbook texture in pixels. |
| `SprayIgnoreClips` | boolean | `false` | Moves the pool above any ancestor that clips its descendants, so particles can leave the frame. |
| `SprayPrewarm` | number | `0` | ImageLabels to build as soon as the Spray is built, the same as calling `:Prewarm()` with that count. |

## From 3D to the screen

One stud is the height in pixels of the GuiObject the emitter sits in. The effect scales with its UI instead of with the screen, so it keeps its look after a resize or on a phone.

`Acceleration` gets its Y flipped because +Y points down in GUI space, so gravity authored as `(0, -10, 0)` still pulls particles down. `EmissionDirection` maps Top, Bottom, Left and Right to the screen, and Front and Back fall back to Top. Only the X of `SpreadAngle` is used, and 180 covers the whole circle.

`ZOffset` is added to the base ZIndex, so emitters stack the way they were authored. Under `ZIndexBehavior.Sibling` a particle can't rise above its host's siblings, though, so if an effect has to sit in front of some other UI, put it under a host that's already in front.

GUI only has normal alpha blending, so `LightEmission` is emulated. Brightness above 1 is tone-mapped toward white, which gives you the blown-out core that additive particles have, and with `SprayGlowLayers` above 1 each particle gets fading halo copies behind it, scaled by `LightEmission`. Overlapping particles still don't add up the way real additive blending would. `LightInfluence` tints the colour toward `Lighting.Ambient`.

Particles move with their parent GuiObject, as if `LockedToPart` were on. Tween the frame and the effect goes with it.

## Performance

Most of what a UI particle costs is the engine writing ImageLabel properties. Spray writes only the ones whose value changed since the last frame, keeps its ImageLabels in a pool, and runs every Spray from a single RenderStepped connection that only exists while something is playing. Against Emitter2D with the same effect, it used about a quarter less CPU per frame on an effect where every property changes on every frame, and about 40% less on one with a flat colour and no spin. The benchmark and how to run it are in [bench](https://github.com/mastedore/spray/blob/main/bench/README.md), and [docs/optimization.md](https://github.com/mastedore/spray/blob/main/docs/optimization.md) goes through what was measured and changed (in Spanish).

## Previewing in Studio

`Spray.Preview` plays emitters in edit mode, without a plugin or a playtest. Select a ParticleEmitter in StarterGui (or anything that contains some) and run this in the command bar:

```lua
require(game.ReplicatedStorage.Packages.Spray.Preview).Play()
```

It loops the selection in bursts. Property changes show up the next time you call `.Play()`. `.Scrub(0.15)` freezes every previewed emitter at one moment, which helps while you edit a Size or Transparency curve, and `.Step(0.02)` nudges that moment forward. Call `.Stop()` before saving, because the preview turns on any hidden UI it needs to show the emitters and `.Stop()` is what turns it back off.

The [Spray plugin](https://github.com/mastedore/spray/blob/main/plugin/README.md) adds a toolbar with Import, Remove, Playground and Preview. Its Preview plays the selected emitters in place with a playback window and rebuilds on every edit. Playground opens a sandbox where you build effects on a stage and export them to StarterGui, with the LocalScript that plays them if you want it. The same playground also runs as a game: [Spray Playground](https://www.roblox.com/games/130730172678468).

## Limitations

- The emitter has to be inside a GuiObject. Emitters on Parts and Attachments aren't drawn.
- `LockedToPart = false` isn't supported, on purpose. Pinning particles to where their parent was when they spawned means keeping history, and not keeping any is what makes scrubbing possible. If you need it, use a second emitter parented higher up.
- `ShapePartial` and `VelocityInheritance` are read but not used yet.
- Textures made for additive blending come out dark on a GUI. Some of Roblox's built-in ones do this (`fire_main`, `fire_sparks`, `forcefield_glow`). Textures with a real alpha channel look right.
- Spray remembers the last 64 `:Emit()` calls. If you call `:Emit()` more often than that within one particle lifetime, the oldest bursts disappear early, so use `Rate` for continuous emission.
- With a flipbook, the first burst after a Spray is built can show the whole sheet for one frame while the texture loads. Slots are reused afterwards, so it doesn't happen again.

## Working on Spray

Rojo and Wally are pinned in `aftman.toml`:

```bash
aftman install
wally install
```

- `rojo serve test.project.json`, then Run in Studio, runs the TestEZ suite and prints the result to the output.
- `rojo serve place.project.json` serves the playground place.
- `rojo build plugin.project.json --plugin SprayPlugin.rbxm` builds the plugin straight into Studio's plugins folder.
- `npx moonwave@1.4.2 dev --code Spray/init.luau --code Spray/Preview.luau` serves the docs site at `localhost:3000` and reloads it when you save. It needs Node.js 18 or newer. The API pages come from the `--[=[ ]=]` comments in those two files, and the guides from `docs/`. Pushing to `main` publishes the site through `.github/workflows/docs.yml`.

## License

Spray is licensed under the [Mozilla Public License 2.0](https://github.com/mastedore/spray/blob/main/LICENSE.md). In plain words, you can use it in anything, open or closed source, free or paid. If you change Spray's own files and share the result, those files stay under MPL-2.0 and their source has to be available. Your own code that uses Spray can be under whatever license you want.


# I'd like to see cool stuff made with Spray! :>
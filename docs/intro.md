---
sidebar_label: Getting started
---

# Getting started

This page takes you from an empty place to a button that throws confetti when you click it. It assumes you've used Roblox Studio before, but not Spray.

## 1. Install Spray

Any of these works:

- With [Wally](https://wally.run), add Spray to the `[dependencies]` of your `wally.toml` and run `wally install`:

  ```toml
  [dependencies]
  Spray = "mastedore/spray@1.0.0"
  ```

  Wally puts it in your `Packages` folder, which most Rojo projects sync to `ReplicatedStorage.Packages`.

- With the Spray Studio plugin, press **Import** on the Spray toolbar. It puts Spray at `ReplicatedStorage.Packages.Spray`.

- Build the model yourself with `rojo build default.project.json -o Spray.rbxm` from a copy of the repository, and drag the file into a folder called `Packages` inside ReplicatedStorage.

The rest of this page assumes Spray is at `ReplicatedStorage.Packages.Spray`. If you put it somewhere else, change the `require` lines to match.

## 2. Put an emitter inside a button

In StarterGui, add a ScreenGui, and inside it a TextButton. Then add a ParticleEmitter inside the TextButton and name it `Confetti`. Your Explorer should look like this:

```
StarterGui
└─ ScreenGui
   └─ TextButton
      └─ Confetti (ParticleEmitter)
```

You won't see anything in the viewport yet, and that's expected. Roblox only draws ParticleEmitters that are inside a Part or an Attachment, so one inside a GUI does nothing until Spray draws it.

## 3. Set up the emitter

Select `Confetti` and edit it in the Properties window, the same way you would a 3D emitter. The one thing that works differently is the unit. In Spray, one stud is the height of the button, so a `Size` of 0.25 gives particles a quarter of the button's height, and a `Speed` of 4 moves them four button heights per second.

A new ParticleEmitter comes with values made for 3D (a `Size` of 1 and a `Lifetime` of 5 to 10 seconds), which look huge and slow on a button. These make a better starting point:

| Property | Value | Why |
| --- | --- | --- |
| `Rate` | `0` | With a `Rate` above 0 the emitter keeps releasing particles for as long as the Spray plays. For a burst on click you want 0. |
| `Lifetime` | `0.8, 1.2` | Each particle lives about a second. |
| `Speed` | `3, 5` | Three to five button heights per second. |
| `SpreadAngle` | `180, 0` | Shoots in every direction. Spray only uses the first number. |
| `Acceleration` | `0, -12, 0` | Gravity. It pulls down on the screen just like in 3D. |
| `Drag` | `2` | Slows the particles down after the initial pop. |
| `Size` | `0.25` | A quarter of the button's height. |

Change the `Color` and `Texture` to whatever you like. Textures with a transparent background look right. Some of Roblox's built-in textures (`fire_main`, `fire_sparks`, `forcefield_glow`) are made for additive blending and come out dark on a GUI.

## 4. Add a LocalScript

Add a LocalScript inside the TextButton, next to `Confetti`, and paste this in:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Spray = require(ReplicatedStorage.Packages.Spray)

local button = script.Parent
local confetti = Spray.New(button.Confetti)

button.Activated:Connect(function()
	confetti:Emit(40)
end)
```

`Spray.New` wraps the emitter once, when the script starts. After that, every click calls `Emit(40)`, which releases 40 particles. It has to be a LocalScript because Spray draws on each player's screen, and a regular Script runs on the server, which has no screen.

Press Play and click the button.

## 5. Preview without pressing Play

You don't need a playtest to see your changes. Select `Confetti` in the Explorer, paste this into Studio's command bar and press Enter:

```lua
require(game.ReplicatedStorage.Packages.Spray.Preview).Play()
```

The emitter plays in bursts, over and over, in the edit viewport. After changing a property, run the line again to see the change. When you're done, run this, and always do it before saving the place:

```lua
require(game.ReplicatedStorage.Packages.Spray.Preview).Stop()
```

The [Preview](/api/Preview) page has the rest, like freezing a burst at one moment.

## If something doesn't work

### The error says the emitter "has no GuiObject ancestor to draw into"

The emitter isn't inside a GUI object. It needs a Frame, TextButton, ImageLabel or other GuiObject somewhere above it.

### Nothing shows up and there's no error

Check that the script is a LocalScript, and that the button is visible and not covered by other UI.

### The particles are huge, tiny, too fast or too slow

Remember that one stud is the button's height. To scale the whole effect at once, add a number attribute called `SprayScale` to the emitter (2 makes it twice as big and twice as fast).

### Particles keep coming after the burst

The emitter's `Rate` is above 0. Set it to 0, or turn `Enabled` off.

### Particles get cut off at the edge of the button

The button, or something above it, has `ClipsDescendants` on. Add a boolean attribute called `SprayIgnoreClips` to the emitter and tick it.

### You changed a property from a script and nothing happened

Spray reads the emitter once. Call `confetti:Cleanup()` after the change, and the next `Emit` reads it again.

## Next

The [Spray API page](/api/Spray) lists every method, every attribute, and how each 3D property translates to the screen.

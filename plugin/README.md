# Spray Plugin
Spray inside Roblox Studio. It adds a **Spray** toolbar with four buttons:

| Button | What it does |
| --- | --- |
| **Import** | Installs the latest Spray at `ReplicatedStorage.Packages.Spray`, replacing the one there. It comes from GitHub (`mastedore/spray`, branch `main`); if GitHub can't be reached, the copy bundled in the plugin goes in instead and the output says so. One undo step. |
| **Remove** | Deletes `ReplicatedStorage.Packages.Spray` (and `Packages`, if that leaves it empty). One undo step. |
| **Playground** | Opens the [playground](playground) in a dock widget. Closing it only hides it, so the stage is kept. |
| **Preview** | Plays the ParticleEmitters selected in Explorer where they are, with the playground's Playback window. Several emitters play as one effect on one timeline, and edits made in the Properties panel show up live. Click again, or close the widget, to stop. |

Inside the plugin's playground, the Origins window has two extra things:

- **+ New > From Studio selection** brings copies of the selected emitters onto the stage, each sized like the GuiObject it was in.
- **Export to Studio** copies the selected origin (or all of them) into `StarterGui` as a throwaway `SprayExport` ScreenGui: a Frame called `OriginVFX` the size of the origin, holding the ParticleEmitter with every edit. With several origins each gets its own `OriginVFX_<Name>` frame, in the same place relative to the middle of the stage. The **+ code** options also write a `PlayVFX` LocalScript that plays it with Spray exactly as it was set up: seed, bursts at their times, loop length, or the frozen frame if it was paused.

## Building
The plugin is built with Rojo from this folder, the `Spray` package and nothing else:

```bash
rojo build plugin.project.json --plugin SprayPlugin.rbxm
```

That writes it straight into Studio's local plugins folder. Add `--watch` to rebuild on every save; Studio reloads it by itself.

## Notes
- HTTP: the first Import makes Studio ask whether the plugin may reach `api.github.com` and `raw.githubusercontent.com`. Declining (or a private repository) just means the bundled copy is installed. Permissions can be changed later in Plugins > Manage Plugins.
- Previewing draws into the place's own UI and turns hidden UI above the emitters on. Spray's pools are never saved with the place, and everything turned on is turned off again on Stop, or when the plugin unloads.
- An origin with `SprayIgnoreClips` on draws above the playground's windows inside the widget, because a widget can't hold separate ScreenGuis the way the game does.

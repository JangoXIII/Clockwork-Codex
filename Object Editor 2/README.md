# OE .whe tools - hand-off package (2026-10-16)

Edit burned `.whe` unit files directly with the shipped Dawn of War: Definitive Edition **Object Editor**.
Tested with DE build 2.10.3.1 (`ObjectEditor.exe` SHA-256 4f18f621…), Windows 11. No Python, Blender or mod-project setup needed.

## Install (once)

1. Copy this folder anywhere, open a command prompt in it and run:

       install.bat "C:\Program Files (x86)\Steam\steamapps\common\Dawn of War Definitive Edition"

   It puts `OpenWhe.exe`, the proxy `d3dx9_43.dll`, a copy of your system `d3dx9_43.dll` as `d3dx9_43_real.dll`, and
   `enable.bat` / `disable.bat` next to `ObjectEditor.exe`. No existing game file is modified or renamed; Steam's
   "verify integrity" ignores the extra files.
2. That is all. Start the Object Editor the way the game expects: from `ModAssistant.exe` with your mod selected
   (Tools menu), or by dragging a `.whe` onto `OpenWhe.exe`. **Double-clicking `ObjectEditor.exe` does not work**,
   with or without these tools: it needs the `-appdir`/`-modname` arguments the Mod Assistant supplies and
   otherwise quits with "Failed to read pipeline.ini".
   The Mod Assistant only enables its Object Editor button for a mod that has a `pipeline.ini`, i.e. one it created itself.
   If your mod lives in the game folder (like `UA_DE`), do this once: File > New Mod, any name (e.g. `WheEdit`), parent
   "Dawn of War: Definitive Edition". Select that mod to launch the Object Editor, then File > Open the `.whe` from wherever it
   really lives; the new mod is only the editor's scratch space and your file is updated in place.
   Simpler: `install.bat` already creates a mod called `WheBridge` in your mods folder; select that one in the Mod Assistant,
   click Object Editor, and File > Open any `.whe`. Its `pipeline.ini` is written with your game path at install time,
   so re-run `install.bat` if the game moves.

If you only want the drag-and-drop launcher and no proxy, copy just `OpenWhe.exe` next to `ObjectEditor.exe`.

**Linux / SteamOS / Steam Deck:** do not run `install.bat`. Use `linux/install.sh "<game dir>"` and `linux/oe.sh` instead; they
run the same files inside the game's Proton prefix. Steps, logs and caveats: `linux/README.md`. Those scripts are **untested on
real hardware** (written without a Linux machine); `--dry-run` shows what they would do.

## Use

* **File > Open** in the Object Editor now lists `Relic EBP or burned WHE (*.EBP;*.WHE)`. Pick a unit's `.whe`
  (its `.whm` must be in the same folder, as in `UltimateApocalypse_THB_test\data\art\ebps\races\...`).
  After ~3 s the unit is loaded with its real textures. They are looked up under the `data\` folder the `.whe` is in
  (as the game does) and in the game's `*SharedTextures*.sga` archives; any that cannot be found show pink, and
  `openwhe.log` lists them (`textures not found ...`). Textures only affect what the editor shows, never the saved `.whe`.
* Edit as usual, **File > Save**. Your `.whe` is updated in place within a second or two; the first time, the original is
  kept beside it as `<unit>.whe.bak`.
* **Recent files** (bottom of the File menu) list the `.whe` files you opened. Picking one re-reads that `.whe` fresh and
  Save writes back to it, exactly like File > Open.
* **File > Open starts in the folder of the last `.whe` you opened** (also after restarting the editor).
* If a `.whe` changes on disk while it is open in the editor (a `git pull`, another tool), Save does **not** overwrite it:
  your save is written next to it as `<unit>.whe.conflict` and `openwhe.log` says so. Compare the two and keep the one you want.
* Without the proxy (or if it has switched itself off): drag the `.whe` onto `OpenWhe.exe` instead - same result.

## When the game updates

The proxy checks the Object Editor build on every start. After an update it switches itself off (one line in
`%APPDATA%\Relic Entertainment\Dawn of War\Mods\WheBridge\proxy.log`), the Object Editor runs exactly as stock, and
`OpenWhe.exe` keeps working. Send that log line back and a matching proxy build can be made. While the proxy is off,
`.whe` entries in the recent-file list give "Unrecognized File Type" (nothing is changed); open those units by dragging the
`.whe` onto `OpenWhe.exe` instead.

`disable.bat` / `enable.bat` in the game directory turn the proxy off and on by hand. Uninstall: delete
`d3dx9_43.dll`, `d3dx9_43_real.dll`, `enable.bat`, `disable.bat`, `OpenWhe.exe`.

## Limits

* `.whe` editing only: model changes still go through Blender; the generated `.sgm` is a stand-in without textures.
* One `.whe` per OpenWhe launch (the proxy path has no such limit).
* Saved files use the Object Editor DE's motion-chunk version 5; the game accepts it (verified in-game) but older third-party
  `.whe` tools may not read it.

## Licences

`OpenWhe.exe` bundles code ported from amorgun's `dow_utils` (object_tool) and `blender_dow`, both GPL-3.0:
see `LICENSE-dow_utils.txt` and `LICENSE-whm2sgm-blender_dow.txt`. The proxy DLL is original code in this project.

Full technical write-up, sources and tests: the `DoW OE` workspace (`README.md`, `tools\openwhe\DEPLOY.md`, `tools\oeproxy\`).

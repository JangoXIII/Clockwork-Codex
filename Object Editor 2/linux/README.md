# OE .whe tools on Linux / SteamOS / Steam Deck

The Object Editor is a Windows program, so on Linux everything in this package runs **inside the game's Proton prefix**,
the same Wine environment Steam uses for the game itself. `install.sh` and `oe.sh` in this folder do that for you;
the Windows pieces (`install.bat`, `OpenWhe.exe`, the proxy `d3dx9_43.dll`) are unchanged.

> **Untested on real hardware.** These scripts were written on a Windows machine with no Linux box or Steam Deck to try them
> on. They are deliberately simple bash and were only exercised against a fake Steam folder layout. Use `--dry-run` first,
> read the output, and please report what breaks (with the command and its output, plus the two log files described below).

## Requirements

* The game installed and **run once from Steam with Proton**, so that `steamapps/compatdata/3556750/pfx` exists.
* bash, coreutils, `python3` (Proton's launcher script is Python; SteamOS has it).
* Optional but recommended: [protontricks](https://github.com/Matoking/protontricks) (`protontricks-launch`), native or the
  Flatpak `com.github.Matoking.protontricks`. With it, `oe.sh` runs programs exactly the way Steam would (inside the Steam
  Linux Runtime). Without it, `oe.sh` calls the `proton` script directly, which usually works too.
  On a Steam Deck the Flatpak needs access to the library the game is in, e.g.
  `flatpak override --user --filesystem=/run/media com.github.Matoking.protontricks`.

## Install (once)

Unpack the whole `OE-whe-tools` folder somewhere (not inside the game folder), then in a terminal (Desktop mode on the Deck):

```bash
chmod +x linux/*.sh
linux/install.sh "/run/media/deck/Cove/SteamLibrary/steamapps/common/Dawn of War Definitive Edition"
```

Without an argument it searches the Steam libraries listed in `libraryfolders.vdf` for the game. What it does:

1. Finds the Steam **app id** from `steamapps/appmanifest_*.acf` (the one whose `installdir` is the game folder; falls back to
   3556750) and the **Proton prefix** `compatdata/<id>/pfx`. The prefix is not always next to the game: on a Steam Deck a game
   on the SD card usually has its prefix on the main drive (`~/.local/share/Steam/steamapps/compatdata/<id>`), so the
   game's library, the Steam root, every library in `libraryfolders.vdf` and `/run/media/*/*/steamapps` are searched.
   If it is still not found the message lists every folder tried; pass `--compatdata /path/to/compatdata/<id>` then.
2. Copies `OpenWhe.exe`, the proxy `d3dx9_43.dll`, `enable.bat`, `disable.bat` and `oe.sh` next to `ObjectEditor.exe`.
   Refuses to overwrite a `d3dx9_43.dll` that is not the proxy. Nothing of the game's is modified or renamed, so
   Steam's "verify integrity" leaves everything alone.
3. Copies the prefix's own `drive_c/windows/system32/d3dx9_43.dll` (a real DLL on current Proton, possibly a symlink into the
   Proton install) to `d3dx9_43_real.dll` in the game folder; the proxy forwards every D3DX call to it. If that file is
   missing or a Wine placeholder stub, it prints the fix (`protontricks 3556750 d3dx9_43` installs Microsoft's DLL into the
   prefix) and continues **without the proxy** - `oe.sh <unit.whe>` works regardless.
4. Runs `OpenWhe.exe --init --game "Z:\...\Dawn of War Definitive Edition"` inside the prefix. That creates the throw-away
   **WheBridge** mod under the prefix's AppData with absolute game paths in its `pipeline.ini`, so the Object Editor can
   load and burn no matter how it was started. Re-run `install.sh` (or `oe.sh init`) if the game moves.

`--no-proxy` installs just the launcher. `--dry-run` prints every command instead of running it.

## Use

`oe.sh` was copied into the game folder, so from there (or with `--game "<game dir>"` from anywhere):

```bash
./oe.sh /path/to/your/mod/data/art/ebps/races/necrons/troops/lychguard.whe
```

opens the `.whe` in the Object Editor through `OpenWhe.exe` (the `.whm` must sit next to it). Edit, **File > Save**: the `.whe`
is updated in place within a second or two, the original kept once as `<unit>.whe.bak`. Close the Object Editor when done.
This route does not need the proxy at all.

With the proxy active you can also use the Object Editor's own File > Open:

```bash
./oe.sh ma      # Mod Assistant: select the WheBridge mod, click its Object Editor button, File > Open any .whe
./oe.sh oe      # the Object Editor directly, started the way the Mod Assistant does (-appdir/-modname WheBridge)
```

File > Open then lists `Relic EBP or burned WHE (*.EBP;*.WHE)`; pick a `.whe`, after ~3 s the unit is loaded, Save writes it back.
Other commands: `./oe.sh info` (what was detected), `./oe.sh logs`, `./oe.sh proxy off|on|status` (what `disable.bat`/`enable.bat`
do on Windows), `./oe.sh run SomeTool.exe args` (anything else inside the prefix with the same environment), `./oe.sh -h`.

### What oe.sh sets

* `WINEDLLOVERRIDES=d3dx9_43=n,b` so Wine loads the proxy from the game folder (`n` = native first) instead of its own built-in
  `d3dx9_43`. Harmless when the proxy is not installed.
* With protontricks: `protontricks-launch --appid <id> <exe> [args]` (Flatpak: `flatpak run --env=... --command=protontricks-launch ...`).
* Without: `STEAM_COMPAT_DATA_PATH=steamapps/compatdata/<id>`, `STEAM_COMPAT_CLIENT_INSTALL_PATH=<Steam root>`,
  `SteamAppId`/`SteamGameId`, then `"<Proton dir>/proton" run <exe> [args]`. The Proton dir is the compat tool Steam assigned to
  the game in `config/config.vdf` (`proton_9`, `proton_experimental`, `GE-Proton9-20`, ...), else the one whose `version` file
  matches `compatdata/<id>/version`, else the newest `Proton N.N` under any library's `steamapps/common`. Override with
  `--proton <dir>` or `PROTON=<dir>`. `--use-proton` / `--use-protontricks` pick the launcher by hand.
* Paths handed to the Windows programs are `Z:\...` (Wine maps `/` to `Z:`), e.g. `--game "Z:\run\media\deck\Cove\SteamLibrary\steamapps\common\Dawn of War Definitive Edition"`.

## Logs and what "passive" means

Both tools log inside the prefix, in the WheBridge mod folder (Wine's `%APPDATA%` for the `steamuser` account):

```
steamapps/compatdata/<id>/pfx/drive_c/users/steamuser/AppData/Roaming/Relic Entertainment/Dawn of War/Mods/WheBridge/
    proxy.log     one line per Object Editor start / .whe opened / failure, written by the proxy d3dx9_43.dll
    openwhe.log   appended on every OpenWhe.exe run (--init, a .whe, the proxy's conversions)
    pipeline.ini  the bridge mod's config with the absolute game paths written by --init
```

`./oe.sh logs` prints the tails of both. Things to look for:

* **No `proxy.log` at all** after starting the Object Editor: the proxy DLL was not loaded. Check `./oe.sh info` says
  `proxy: on`, and that the launch went through `oe.sh` (the override is set there; Steam's own game launch does not load it,
  nor should it). Try the other launcher (`--use-proton` / `--use-protontricks`): protontricks may not pass the override through.
* **`passive: unknown ObjectEditor.exe build ... sha256=...`**: the safety switch. The proxy only patches the Object Editor build
  it was made for (SHA-256 of `ObjectEditor.exe`). The prefix's `mfc140.dll` (VC++ runtime) may be any 14.x build: it is checked
  by version and by its exports, not by hash, and `active:` lines name it. On a passive start the Object Editor runs **exactly as
  stock** (Open lists `.ebp` only) and nothing is broken. Send that log line back: a proxy build with the extra hash is a one-line
  change. Until then use the **OpenWhe fallback**: `./oe.sh unit.whe` does the same edit-and-save-in-place without the proxy.
* **`passive: mfc140.dll is not loaded`** / other `passive:` lines: same conclusion, OpenWhe still works; send the line.
* **Object Editor does not start at all with the proxy on**, or Wine complains about `d3dx9_43_real.dll`: the forwarding target is
  unusable (e.g. the prefix's DLL was a stub). `./oe.sh proxy off`, then either live with the OpenWhe route or install Microsoft's
  DLL into the prefix (`protontricks <id> d3dx9_43`) and re-run `install.sh`.
* **`openwhe.log` says `ObjectEditor.exe not found`**: the `--game` path did not survive; run `./oe.sh -v info` and check the game
  dir, then `./oe.sh init`.
* **"Unable to burn the EBP!"** on Save after File > Open, and `proxy.log` says `open ... -> ...\Dawn of War Definitive Edition\DXP2\...`:
  the Object Editor ran in the game folder instead of the WheBridge mod. Fixed in `oe.sh` (2026-11-16), which now passes
  `-wkdir` to the mod; replace `oe.sh` in the game folder with this one. The old version left `<unit>.ebp` and `<unit>.sgm`
  under `<game>/DXP2/DataGeneric/art/...` (the stock game has no `DXP2/DataGeneric` folder; the exact paths are in `proxy.log`),
  which can be deleted.
* **"Failed to read pipeline.ini"** from the Object Editor: it was started without `-appdir`/`-modname` (e.g. by double-click in a
  file manager). Use `./oe.sh oe`, `./oe.sh ma` or `./oe.sh unit.whe`.

Graphics trouble in the Object Editor (black viewport, crash on load) is a Proton D3D9 question, not this package: try
`PROTON_USE_WINED3D=1 ./oe.sh ...` to swap DXVK for Wine's own D3D9.

## Uninstall

Delete `d3dx9_43.dll`, `d3dx9_43_real.dll`, `enable.bat`, `disable.bat`, `OpenWhe.exe`, `oe.sh` from the game folder, and the
`WheBridge` mod folder in the prefix (path above) if you want the logs gone too.

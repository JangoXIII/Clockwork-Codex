#!/usr/bin/env bash
# install.sh - Linux / SteamOS / Steam Deck installer for the OE .whe tools (the counterpart of ..\install.bat).
#
# UNTESTED ON REAL HARDWARE: written on Windows without a Linux machine. Read README.md in this folder first;
# --dry-run shows what would be done. Please report what breaks.
#
#   ./install.sh "/path/to/steamapps/common/Dawn of War Definitive Edition"      (no argument: search the Steam libraries)
#   ./install.sh --no-proxy "<game dir>"      launcher only (OpenWhe.exe), no proxy DLL
#   other options are passed on to oe.sh: --use-proton | --use-protontricks, --proton <dir>, --compatdata <dir>, --dry-run, -v
#   (--compatdata: the steamapps/compatdata/<appid> folder when it is not found automatically; on a Steam Deck the prefix
#    of a game on the SD card normally lives on the main drive, which is searched by default)
#
# What it does (nothing of the game's is modified or renamed, Steam's "verify integrity" ignores the extra files):
#   1. finds the Steam app id (steamapps/appmanifest_*.acf) and the Proton prefix (steamapps/compatdata/<id>/pfx)
#   2. copies OpenWhe.exe, the proxy d3dx9_43.dll, enable.bat, disable.bat and oe.sh next to ObjectEditor.exe
#   3. copies the prefix's own drive_c/windows/system32/d3dx9_43.dll as d3dx9_43_real.dll (the proxy forwards to it)
#   4. runs `OpenWhe.exe --init --game Z:\...` inside the prefix: creates the WheBridge mod with absolute game paths
# Without the proxy (--no-proxy, or no usable d3dx9_43.dll in the prefix) `oe.sh <unit.whe>` still works.

set -eu

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
PKG=$(dirname -- "$HERE")                    # the OE-whe-tools folder with OpenWhe.exe, d3dx9_43.dll, *.bat
NO_PROXY=0
GAME_ARG=
PASS=()

while [ $# -gt 0 ]; do
    case $1 in
        --no-proxy) NO_PROXY=1; shift ;;
        --dry-run|-v|--use-proton|--use-protontricks) PASS+=("$1"); shift ;;
        --proton) [ $# -ge 2 ] || { echo "install.sh: --proton needs a directory" >&2; exit 1; }; PASS+=("$1" "$2"); shift 2 ;;
        --compatdata) [ $# -ge 2 ] || { echo "install.sh: --compatdata needs a directory" >&2; exit 1; }; PASS+=("$1" "$2"); shift 2 ;;
        --game)   [ $# -ge 2 ] || { echo "install.sh: --game needs a directory" >&2; exit 1; }; GAME_ARG=$2; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "install.sh: unknown option $1" >&2; exit 1 ;;
        *)  GAME_ARG=$1; shift ;;
    esac
done

[ -f "$HERE/oe.sh" ] || { echo "install.sh: oe.sh must sit next to this script" >&2; exit 1; }
# shellcheck source=oe.sh
. "$HERE/oe.sh"                              # functions only: detect, winpath, run_in_prefix, ...
die()  { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
note() { printf 'install.sh: %s\n' "$*" >&2; }
[ -n "$GAME_ARG" ] && OPT_GAME=$GAME_ARG
for a in "${PASS[@]}"; do
    case $a in --dry-run) DRY_RUN=1 ;; -v) VERBOSE=1 ;; --use-proton) OPT_LAUNCHER=proton ;; --use-protontricks) OPT_LAUNCHER=protontricks ;; esac
done
for ((i = 0; i < ${#PASS[@]}; i++)); do [ "${PASS[i]}" = --proton ] && OPT_PROTON=${PASS[i+1]}; [ "${PASS[i]}" = --compatdata ] && OPT_COMPATDATA=${PASS[i+1]}; done
if [ "$OPT_LAUNCHER" = protontricks ] && ! command -v protontricks-launch >/dev/null 2>&1; then
    if command -v flatpak >/dev/null 2>&1 && flatpak info "$PROTONTRICKS_FLATPAK" >/dev/null 2>&1; then OPT_LAUNCHER=flatpak
    else die "protontricks-launch is not installed (neither native nor the Flatpak $PROTONTRICKS_FLATPAK)"; fi
fi

detect
print_info
echo

for f in OpenWhe.exe d3dx9_43.dll enable.bat disable.bat; do
    [ -f "$PKG/$f" ] || die "$f is missing from \"$PKG\" (unpack the whole OE-whe-tools folder)"
done

run() { if [ "$DRY_RUN" = 1 ]; then printf '[dry-run]'; printf ' %q' "$@"; printf '\n'; else "$@"; fi; }

# --- proxy: refuse to overwrite a foreign d3dx9_43.dll, then make d3dx9_43_real.dll from the prefix's copy
PROXY_OK=0
if [ "$NO_PROXY" = 0 ]; then
    if [ -f "$GAME/d3dx9_43.dll" ] && ! grep -aq oeproxy "$GAME/d3dx9_43.dll"; then
        die "\"$GAME/d3dx9_43.dll\" already exists and is not the OE proxy - not touching it (use --no-proxy to install only the launcher)"
    fi
    REAL="$PFX/drive_c/windows/system32/d3dx9_43.dll"
    if [ ! -e "$REAL" ]; then
        note "WARNING: \"$REAL\" does not exist, so the proxy cannot be installed (it needs a real d3dx9_43.dll to forward to)."
        note "         Fix: install the DirectX d3dx9_43 runtime into the prefix, e.g.  protontricks $APPID d3dx9_43  , then re-run this script."
        note "         Continuing without the proxy: oe.sh <unit.whe> (OpenWhe.exe) works without it."
    elif grep -aq "Wine placeholder DLL" "$REAL" 2>/dev/null; then
        note "WARNING: \"$REAL\" is a Wine placeholder stub, not a usable DLL; the proxy cannot forward to it."
        note "         Fix:  protontricks $APPID d3dx9_43  (installs Microsoft's d3dx9_43.dll into the prefix), then re-run this script."
        note "         Continuing without the proxy: oe.sh <unit.whe> (OpenWhe.exe) works without it."
    else
        run cp -L -f -- "$REAL" "$GAME/d3dx9_43_real.dll"       # -L: the prefix may hold a symlink into the Proton install
        run cp -f -- "$PKG/d3dx9_43.dll" "$GAME/d3dx9_43.dll"
        [ -f "$GAME/d3dx9_43.dll.off" ] && run rm -f -- "$GAME/d3dx9_43.dll.off"
        PROXY_OK=1
    fi
fi

# --- launcher, switches, this script's companion
run cp -f -- "$PKG/OpenWhe.exe" "$GAME/OpenWhe.exe"
run cp -f -- "$PKG/enable.bat" "$PKG/disable.bat" "$GAME/"
run cp -f -- "$HERE/oe.sh" "$GAME/oe.sh"
run chmod +x -- "$GAME/oe.sh" "$GAME/OpenWhe.exe"

# --- bridge mod with absolute (Z:) game paths, so the Object Editor can burn even when started with -wkdir only
echo
echo "Creating the $MOD_NAME mod inside the prefix (OpenWhe.exe --init) ..."
if run_in_prefix "$GAME/OpenWhe.exe" --init --game "$(winpath "$GAME")"; then
    [ "$DRY_RUN" = 1 ] || [ -f "$BRIDGE_DIR/pipeline.ini" ] || note "WARNING: OpenWhe.exe --init returned 0 but \"$BRIDGE_DIR/pipeline.ini\" is missing"
else
    note "WARNING: OpenWhe.exe --init failed (exit $?). Check \"$BRIDGE_DIR/openwhe.log\" and the output above;"
    note "         try again with \`$GAME/oe.sh init\` (add --use-proton or --use-protontricks to switch launcher)."
fi

echo
echo "Installed into \"$GAME\":"
echo "  OpenWhe.exe, oe.sh, enable.bat, disable.bat$( [ "$PROXY_OK" = 1 ] && printf ', d3dx9_43.dll (proxy), d3dx9_43_real.dll' )"
[ "$PROXY_OK" = 1 ] || echo "  (proxy NOT installed - see the warnings above; OpenWhe still works)"
echo "Next:"
echo "  \"$GAME/oe.sh\" /path/to/unit.whe        open a .whe in the Object Editor (its .whm must sit next to it); File > Save writes it back"
echo "  \"$GAME/oe.sh\" ma                       Mod Assistant: select $MOD_NAME, click Object Editor, File > Open a .whe (needs the proxy)"
echo "  \"$GAME/oe.sh\" logs                     proxy.log / openwhe.log from $BRIDGE_DIR"

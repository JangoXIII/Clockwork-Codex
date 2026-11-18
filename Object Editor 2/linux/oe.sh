#!/usr/bin/env bash
# oe.sh - run the Dawn of War: Definitive Edition tools inside the game's Proton prefix (Linux / SteamOS / Steam Deck).
#
# UNTESTED ON REAL HARDWARE: written on Windows without a Linux machine. Read README.md in this folder first and
# use --dry-run to see what would be executed. Please report what breaks.
#
#   oe.sh [options] ma                  Mod Assistant (select the WheBridge mod, then its Object Editor button)
#   oe.sh [options] oe                  Object Editor directly, started like the Mod Assistant does (-appdir/-modname WheBridge)
#   oe.sh [options] <unit.whe>          OpenWhe.exe <unit.whe>: open a burned .whe in the Object Editor, Save writes it back
#   oe.sh [options] init                OpenWhe.exe --init: (re)create the WheBridge mod in the prefix (install.sh does this)
#   oe.sh [options] run <exe> [args..]  any .exe (path on this machine or inside the game dir) with the same environment
#   oe.sh [options] proxy on|off|status turn the proxy d3dx9_43.dll off/on by renaming it (what enable.bat/disable.bat do)
#   oe.sh [options] logs                print proxy.log and openwhe.log from inside the prefix
#   oe.sh [options] info                print what was detected and exit
#
# Options:
#   --game <dir>          game directory (default: the folder this script is in, $DOW_GAME_DIR, or a search of the Steam libraries)
#   --compatdata <dir>    the game's steamapps/compatdata/<appid> folder (holds pfx/). Default: searched in the game's library,
#                         the Steam root and every other library (on a Steam Deck the prefix of an SD-card game is usually
#                         on the main drive); $STEAM_COMPAT_DATA_PATH is honoured too
#   --proton <dir>        Proton to use (a folder containing the `proton` script); default: the game's compat tool from
#                         Steam's config.vdf, else the Proton that created the prefix, else the newest installed one
#   --use-protontricks    force protontricks-launch (default when it is installed, native or Flatpak)
#   --use-proton          force running the Proton script directly
#   --dry-run             print the command instead of running it
#   -v                    chatty
# Environment: STEAM_ROOT (Steam install, e.g. ~/.local/share/Steam), DOW_GAME_DIR, PROTON (same as --proton).
#
# The Object Editor must be started with -appdir/-modname (OpenWhe and the Mod Assistant do that); double-clicking
# ObjectEditor.exe does not work on Windows either. WINEDLLOVERRIDES=d3dx9_43=n,b makes Wine load the proxy from the game
# directory instead of its own d3dx9_43; without the proxy everything still works through OpenWhe.exe.

set -eu

DEFAULT_APPID=3556750                         # Warhammer 40,000: Dawn of War - Definitive Edition
GAME_INSTALLDIR_DEFAULT="Dawn of War Definitive Edition"
MOD_NAME=WheBridge
PROTONTRICKS_FLATPAK=com.github.Matoking.protontricks

OPT_GAME=${DOW_GAME_DIR:-}
OPT_PROTON=${PROTON:-}
OPT_COMPATDATA=${OPT_COMPATDATA:-}
OPT_LAUNCHER=
DRY_RUN=0
VERBOSE=0

die()  { printf 'oe.sh: %s\n' "$*" >&2; exit 1; }
note() { printf 'oe.sh: %s\n' "$*" >&2; }
vlog() { [ "$VERBOSE" = 1 ] && printf 'oe.sh: %s\n' "$*" >&2 || true; }

# Linux absolute path -> Wine path on the Z: drive (Z: is / in every Wine/Proton prefix).
winpath() {
    local p; p=$(realpath -m -- "$1")
    printf 'Z:%s' "${p//\//\\}"
}

# ---------------------------------------------------------------- Steam locations
find_steam_root() {
    local d
    for d in "${STEAM_ROOT:-}" "$HOME/.steam/root" "$HOME/.steam/steam" "$HOME/.local/share/Steam" \
             "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam" "$HOME/.steam/debian-installation"; do
        [ -n "$d" ] && [ -d "$d/steamapps" ] && { readlink -f -- "$d"; return 0; }
    done
    return 1
}

# All Steam library folders (the Steam root plus every "path" in libraryfolders.vdf), one per line.
steam_libraries() {
    local root=$1 f
    {
        printf '%s\n' "$root"
        for f in "$root/steamapps/libraryfolders.vdf" "$root/config/libraryfolders.vdf"; do
            [ -f "$f" ] || continue
            sed -nE 's/^[[:space:]]*"path"[[:space:]]+"([^"]*)".*/\1/p' "$f"
        done
    } | awk '!seen[$0]++'
}

find_game_dir() {
    local here cand lib
    if [ -n "$OPT_GAME" ]; then
        [ -f "$OPT_GAME/ObjectEditor.exe" ] || die "ObjectEditor.exe not found in \"$OPT_GAME\""
        readlink -f -- "$OPT_GAME"; return 0
    fi
    here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    [ -f "$here/ObjectEditor.exe" ] && { printf '%s\n' "$here"; return 0; }
    if [ -n "${STEAM_ROOT_DETECTED:-}" ]; then
        while IFS= read -r lib; do
            cand="$lib/steamapps/common/$GAME_INSTALLDIR_DEFAULT"
            [ -f "$cand/ObjectEditor.exe" ] && { readlink -f -- "$cand"; return 0; }
        done < <(steam_libraries "$STEAM_ROOT_DETECTED")
    fi
    for cand in /run/media/*/*/steamapps/common/"$GAME_INSTALLDIR_DEFAULT" /run/media/*/steamapps/common/"$GAME_INSTALLDIR_DEFAULT"; do
        [ -f "$cand/ObjectEditor.exe" ] && { readlink -f -- "$cand"; return 0; }
    done
    die "game directory not found; pass --game \"/path/to/steamapps/common/$GAME_INSTALLDIR_DEFAULT\""
}

# App id from steamapps/appmanifest_*.acf whose "installdir" is the game folder's name.
find_appid() {
    local steamapps=$1 name=$2 m id esc
    esc=$(printf '%s' "$name" | sed 's/[][\.*^$/]/\\&/g')
    for m in "$steamapps"/appmanifest_*.acf; do
        [ -f "$m" ] || continue
        if grep -qE "^[[:space:]]*\"installdir\"[[:space:]]+\"$esc\"" "$m"; then
            id=${m##*/appmanifest_}; printf '%s\n' "${id%.acf}"; return 0
        fi
    done
    if [ -d "$steamapps/compatdata/$DEFAULT_APPID" ]; then
        note "no appmanifest names \"$name\"; assuming app id $DEFAULT_APPID (its compatdata exists)"
        printf '%s\n' "$DEFAULT_APPID"; return 0
    fi
    die "no appmanifest_*.acf in \"$steamapps\" has installdir \"$name\" and no compatdata/$DEFAULT_APPID: has the game been run once from Steam?"
}

# Compat tool Steam assigned to the app (or to all apps, key "0") in config/config.vdf, e.g. proton_9, proton_experimental, GE-Proton9-20.
compat_tool_name() {
    local root=$1 appid=$2 f="$1/config/config.vdf"
    [ -f "$f" ] || return 0
    awk -v id="\"$appid\"" '
        !inmap && /"CompatToolMapping"/ { inmap = 1; depth = 0; next }
        inmap {
            if ($0 ~ /\{/) depth++
            if ($0 ~ /\}/) { depth--; if (depth <= 0) exit; if (depth == 1) key = "" }
            if (depth == 1 && $1 ~ /^"/) key = $1
            if (depth == 2 && $1 == "\"name\"") { v = $2; gsub(/"/, "", v); if (key == id) { app = v } else if (key == "\"0\"") { def = v } }
        }
        END { if (app != "") print app; else if (def != "") print def }' "$f"
}

# Every installed Proton folder (contains a `proton` script), one per line.
proton_candidates() {
    local root=$1 lib d
    {
        while IFS= read -r lib; do
            for d in "$lib"/steamapps/common/Proton*/; do [ -f "$d/proton" ] && printf '%s\n' "${d%/}"; done
        done < <(steam_libraries "$root")
        for d in "$root"/compatibilitytools.d/*/ "$HOME"/.steam/root/compatibilitytools.d/*/ "$HOME"/.local/share/Steam/compatibilitytools.d/*/; do
            [ -f "$d/proton" ] && printf '%s\n' "${d%/}"
        done
    } 2>/dev/null | awk '!seen[$0]++'
}

find_proton() {
    local root=$1 appid=$2 compatdata=$3 tool cands pat pfxver d v
    if [ -n "$OPT_PROTON" ]; then
        [ -f "$OPT_PROTON/proton" ] || die "no \`proton\` script in \"$OPT_PROTON\""
        printf '%s\n' "$OPT_PROTON"; return 0
    fi
    cands=$(proton_candidates "$root")
    [ -n "$cands" ] || die "no Proton installation found under steamapps/common or compatibilitytools.d; pass --proton <dir>"

    # 1. the tool Steam assigned to the game
    tool=$(compat_tool_name "$root" "$appid")
    vlog "compat tool from config.vdf: ${tool:-<none>}"
    if [ -n "$tool" ]; then
        case $tool in
            proton_experimental) pat='Proton - Experimental' ;;
            proton_hotfix)       pat='Proton Hotfix' ;;
            proton_[0-9]*)       v=${tool#proton_}
                                 case $v in 513) pat='Proton 5.13' ;; 411) pat='Proton 4.11' ;; 316) pat='Proton 3.16' ;;
                                            ??) pat="Proton ${v:0:1}.${v:1}" ;; *) pat="Proton $v.0" ;; esac ;;
            *)                   pat=$tool ;;   # GE-Proton9-20 etc.: folder named like the tool
        esac
        d=$(printf '%s\n' "$cands" | awk -v p="$pat" 'BEGIN{n=length(p)} {b=$0; sub(/.*\//,"",b); if (substr(b,1,n)==p) print}' | sort -V | tail -n 1)
        [ -n "$d" ] && { printf '%s\n' "$d"; return 0; }
        note "Steam assigns \"$tool\" to the game but no matching Proton folder was found; falling back"
    fi
    # 2. the Proton that last ran in this prefix (compatdata/<id>/version vs <proton>/version)
    if [ -f "$compatdata/version" ]; then
        pfxver=$(head -n 1 "$compatdata/version" | tr -d '[:space:]')
        if [ -n "$pfxver" ]; then
            while IFS= read -r d; do
                [ -f "$d/version" ] && grep -qF -- "$pfxver" "$d/version" && { printf '%s\n' "$d"; return 0; }
            done <<< "$cands"
            vlog "prefix version \"$pfxver\" matches no installed Proton"
        fi
    fi
    # 3. newest numbered Proton, else Experimental, else Hotfix, else anything
    d=$(printf '%s\n' "$cands" | grep -E '/Proton [0-9]+\.[0-9]+' | sort -V | tail -n 1 || true)
    [ -n "$d" ] || d=$(printf '%s\n' "$cands" | grep -F '/Proton - Experimental' | head -n 1 || true)
    [ -n "$d" ] || d=$(printf '%s\n' "$cands" | grep -F '/Proton Hotfix' | head -n 1 || true)
    [ -n "$d" ] || d=$(printf '%s\n' "$cands" | sort -V | tail -n 1)
    printf '%s\n' "$d"
}

find_launcher() {
    if [ -n "$OPT_LAUNCHER" ]; then printf '%s\n' "$OPT_LAUNCHER"; return 0; fi
    if command -v protontricks-launch >/dev/null 2>&1; then printf 'protontricks\n'; return 0; fi
    if command -v flatpak >/dev/null 2>&1 && flatpak info "$PROTONTRICKS_FLATPAK" >/dev/null 2>&1; then printf 'flatpak\n'; return 0; fi
    printf 'proton\n'
}

# The compatdata/<appid> folder holding the Proton prefix. Steam does not always keep it next to the game: on a Steam Deck
# a game on the SD card can have its prefix under the main drive's ~/.local/share/Steam/steamapps/compatdata. Search order:
# --compatdata / $STEAM_COMPAT_DATA_PATH, the game's own library, the Steam root, every library in libraryfolders.vdf,
# then any /run/media/*/*/steamapps (SD cards and external drives).
find_compatdata() {
    local steamapps=$1 appid=$2 c lib tried=()
    if [ -n "${OPT_COMPATDATA:-}" ]; then
        c=${OPT_COMPATDATA%/}; [ "$(basename -- "$c")" = pfx ] && c=$(dirname -- "$c")
        [ -d "$c/pfx/drive_c" ] || die "--compatdata \"$c\": no Proton prefix there (expected $c/pfx/drive_c)"
        readlink -f -- "$c"; return 0
    fi
    if [ -n "${STEAM_COMPAT_DATA_PATH:-}" ] && [ -d "$STEAM_COMPAT_DATA_PATH/pfx/drive_c" ]; then
        readlink -f -- "$STEAM_COMPAT_DATA_PATH"; return 0
    fi
    {
        printf '%s
' "$steamapps/compatdata/$appid"
        [ -n "${STEAM_ROOT_DETECTED:-}" ] && printf '%s
' "$STEAM_ROOT_DETECTED/steamapps/compatdata/$appid"
        [ -n "${STEAM_ROOT_DETECTED:-}" ] && while IFS= read -r lib; do
            printf '%s
' "$lib/steamapps/compatdata/$appid"
        done < <(steam_libraries "$STEAM_ROOT_DETECTED")
        for lib in /run/media/*/*/steamapps /run/media/*/steamapps "$HOME"/.local/share/Steam/steamapps                    "$HOME"/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps; do
            [ -d "$lib" ] && printf '%s
' "$lib/compatdata/$appid"
        done
    } | awk '!seen[$0]++' > "${TMPDIR:-/tmp}/oe_compat_$$"
    while IFS= read -r c; do
        tried+=("$c")
        if [ -d "$c/pfx/drive_c" ]; then rm -f -- "${TMPDIR:-/tmp}/oe_compat_$$"; readlink -f -- "$c"; return 0; fi
    done < "${TMPDIR:-/tmp}/oe_compat_$$"
    rm -f -- "${TMPDIR:-/tmp}/oe_compat_$$"
    die "no Proton prefix for app $appid. Looked for <compatdata>/pfx/drive_c in:$(printf '
  %s' "${tried[@]}")
Run the game once from Steam (with Proton) so Steam creates it, or pass --compatdata /path/to/steamapps/compatdata/$appid"
}

# Fills GAME STEAMAPPS APPID COMPATDATA PFX STEAM_ROOT_DETECTED PROTON_DIR LAUNCHER BRIDGE_DIR.
detect() {
    STEAM_ROOT_DETECTED=$(find_steam_root || true)
    GAME=$(find_game_dir)
    STEAMAPPS=$(dirname -- "$(dirname -- "$GAME")")
    [ -d "$STEAMAPPS/compatdata" ] || [ "$(basename -- "$STEAMAPPS")" = steamapps ] \
        || die "\"$GAME\" is not under a steamapps/common folder; the Proton prefix cannot be located"
    APPID=$(find_appid "$STEAMAPPS" "$(basename -- "$GAME")")
    COMPATDATA=$(find_compatdata "$STEAMAPPS" "$APPID")
    PFX="$COMPATDATA/pfx"
    BRIDGE_DIR="$PFX/drive_c/users/steamuser/AppData/Roaming/Relic Entertainment/Dawn of War/Mods/$MOD_NAME"
    LAUNCHER=$(find_launcher)
    PROTON_DIR=
    if [ "$LAUNCHER" = proton ]; then
        [ -n "$STEAM_ROOT_DETECTED" ] || die "Steam installation not found (set STEAM_ROOT=/path/to/Steam)"
        PROTON_DIR=$(find_proton "$STEAM_ROOT_DETECTED" "$APPID" "$COMPATDATA")
    fi
}

proxy_state() {
    if [ -f "$GAME/d3dx9_43.dll" ]; then echo "on (d3dx9_43.dll)"
    elif [ -f "$GAME/d3dx9_43.dll.off" ]; then echo "off (d3dx9_43.dll.off)"
    else echo "not installed"; fi
}

print_info() {
    printf 'game dir     : %s\n' "$GAME"
    printf 'app id       : %s\n' "$APPID"
    printf 'prefix       : %s\n' "$PFX"
    printf 'Steam root   : %s\n' "${STEAM_ROOT_DETECTED:-<not found>}"
    printf 'launcher     : %s%s\n' "$LAUNCHER" "${PROTON_DIR:+ ($PROTON_DIR)}"
    printf 'bridge mod   : %s%s\n' "$BRIDGE_DIR" "$( [ -d "$BRIDGE_DIR" ] || printf ' (not created yet)' )"
    printf 'proxy        : %s\n' "$(proxy_state)"
    printf 'OpenWhe.exe  : %s\n' "$( [ -f "$GAME/OpenWhe.exe" ] && echo present || echo MISSING )"
}

# run_in_prefix <exe on this machine or inside the game dir> [args...]
run_in_prefix() {
    local exe=$1; shift
    if [ ! -f "$exe" ]; then
        if [ -f "$GAME/$exe" ]; then exe="$GAME/$exe"
        elif [ "$DRY_RUN" != 1 ]; then die "executable not found: $exe"; fi
    fi
    exe=$(readlink -f -- "$exe")
    local ovr="d3dx9_43=n,b${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"
    local -a cmd
    case $LAUNCHER in
        protontricks)
            export WINEDLLOVERRIDES=$ovr
            cmd=(protontricks-launch --appid "$APPID" "$exe" "$@") ;;
        flatpak)
            cmd=(flatpak run --env="WINEDLLOVERRIDES=$ovr" --command=protontricks-launch "$PROTONTRICKS_FLATPAK" --appid "$APPID" "$exe" "$@") ;;
        proton)
            export WINEDLLOVERRIDES=$ovr
            export STEAM_COMPAT_DATA_PATH=$COMPATDATA
            export STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_ROOT_DETECTED
            export STEAM_COMPAT_APP_ID=$APPID SteamAppId=$APPID SteamGameId=$APPID
            cmd=("$PROTON_DIR/proton" run "$exe" "$@") ;;
        *) die "unknown launcher \"$LAUNCHER\"" ;;
    esac
    if [ "$DRY_RUN" = 1 ]; then
        printf '[dry-run] cd %q\n' "$PWD"
        case $LAUNCHER in
            proton) printf '[dry-run] WINEDLLOVERRIDES=%q STEAM_COMPAT_DATA_PATH=%q STEAM_COMPAT_CLIENT_INSTALL_PATH=%q \\\n' "$ovr" "$COMPATDATA" "$STEAM_ROOT_DETECTED" ;;
            protontricks) printf '[dry-run] WINEDLLOVERRIDES=%q \\\n' "$ovr" ;;
        esac
        printf '[dry-run]'; printf ' %q' "${cmd[@]}"; printf '\n'
        return 0
    fi
    vlog "running: ${cmd[*]}"
    "${cmd[@]}"
}

proxy_switch() {
    case $1 in
        on)     if [ -f "$GAME/d3dx9_43.dll.off" ]; then mv -- "$GAME/d3dx9_43.dll.off" "$GAME/d3dx9_43.dll"; echo "OE proxy enabled"
                else echo "OE proxy already enabled (or not installed)"; fi ;;
        off)    if [ -f "$GAME/d3dx9_43.dll" ]; then mv -- "$GAME/d3dx9_43.dll" "$GAME/d3dx9_43.dll.off"; echo "OE proxy disabled"
                else echo "OE proxy already disabled"; fi ;;
        status) echo "proxy: $(proxy_state)" ;;
        *)      die "proxy on|off|status" ;;
    esac
}

show_logs() {
    local f
    for f in proxy.log openwhe.log; do
        printf '==== %s\n' "$BRIDGE_DIR/$f"
        if [ -f "$BRIDGE_DIR/$f" ]; then tail -n 40 -- "$BRIDGE_DIR/$f"; else echo "(no such file yet)"; fi
    done
}

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

main() {
    local -a rest=()
    while [ $# -gt 0 ]; do
        case $1 in
            --game)   [ $# -ge 2 ] || die "--game needs a directory"; OPT_GAME=$2; shift 2 ;;
            --proton) [ $# -ge 2 ] || die "--proton needs a directory"; OPT_PROTON=$2; shift 2 ;;
            --compatdata) [ $# -ge 2 ] || die "--compatdata needs a directory"; OPT_COMPATDATA=$2; shift 2 ;;
            --use-protontricks) OPT_LAUNCHER=protontricks; shift ;;
            --use-proton)       OPT_LAUNCHER=proton; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -v)        VERBOSE=1; shift ;;
            -h|--help) usage 0 ;;
            --) shift; rest+=("$@"); break ;;
            *)  rest+=("$1"); shift ;;
        esac
    done
    [ ${#rest[@]} -gt 0 ] || usage 1
    if [ "$OPT_LAUNCHER" = protontricks ] && ! command -v protontricks-launch >/dev/null 2>&1; then
        if command -v flatpak >/dev/null 2>&1 && flatpak info "$PROTONTRICKS_FLATPAK" >/dev/null 2>&1; then OPT_LAUNCHER=flatpak
        else die "protontricks-launch is not installed (neither native nor the Flatpak $PROTONTRICKS_FLATPAK)"; fi
    fi
    detect
    local what=${rest[0]}
    rest=("${rest[@]:1}")
    case $what in
        info)  print_info ;;
        logs)  show_logs ;;
        proxy) proxy_switch "${rest[0]:-status}" ;;
        ma)    run_in_prefix "$GAME/ModAssistant.exe" "${rest[@]}" ;;
        oe)    if [ -d "$BRIDGE_DIR" ]; then cd -- "$BRIDGE_DIR"
               else note "bridge mod \"$BRIDGE_DIR\" does not exist yet; run \`oe.sh init\` first (or install.sh)"; fi
               # -wkdir: protontricks-launch starts the program in its own folder (the game dir), whose pipeline.ini
               # has no WheBridge project, so the working directory set above is not enough (Save then fails with
               # "Unable to burn the EBP!"). The same folder as BRIDGE_DIR, as Windows programs in the prefix see it.
               run_in_prefix "$GAME/ObjectEditor.exe" -appdir "$(winpath "$GAME")" -modname "$MOD_NAME" \
                   -wkdir "C:\\users\\steamuser\\AppData\\Roaming\\Relic Entertainment\\Dawn of War\\Mods\\$MOD_NAME" "${rest[@]}" ;;
        init)  run_in_prefix "$GAME/OpenWhe.exe" --init --game "$(winpath "$GAME")" "${rest[@]}" ;;
        run)   [ ${#rest[@]} -ge 1 ] || die "run <exe> [args]"; run_in_prefix "${rest[@]}" ;;
        *.whe|*.WHE)
               [ -f "$what" ] || die "no such file: $what"
               [ -f "$GAME/OpenWhe.exe" ] || die "OpenWhe.exe is not in \"$GAME\"; run install.sh first"
               run_in_prefix "$GAME/OpenWhe.exe" --game "$(winpath "$GAME")" "$(winpath "$what")" "${rest[@]}" ;;
        *)     die "unknown command \"$what\" (ma | oe | init | run | proxy | logs | info | <unit.whe>); -h for help" ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi

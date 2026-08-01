{ lib
, writeShellApplication
, coreutils
, gawk
, gnugrep
, spout2pw
}:

# Seeds a Wine prefix with Spout2PW: the fakedll stubs for spout2pw.exe and
# spoutdxtoc.dll, plus the Spout2Pw service registration.
#
# This drives Proton's own `rundll32 setupapi.dll,InstallHinfSection` rather
# than hand-writing PE stubs and registry keys, so Wine generates them itself.
# It is the same work the launcher's prepare_prefix() does, just without having
# to wrap the game's launch command.
writeShellApplication {
  name = "spout2pw-install";

  runtimeInputs = [ coreutils gawk gnugrep ];

  text = ''
    default_payload="''${XDG_DATA_HOME:-$HOME/.local/share}/spout2pw"
    packaged_payload=${lib.escapeShellArg "${spout2pw}/share/spout2pw"}

    appid=""
    proton=""
    payload=""
    prefix=""
    compat_data=""
    uninstall=0

    usage() {
      cat <<'USAGE'
    Usage: spout2pw-install --appid ID [options]
           spout2pw-install --prefix DIR --proton DIR [options]

    Installs Spout2PW into a Proton/Wine prefix (fakedll stubs + service entry).

    Options:
      --appid ID       Steam AppID, e.g. 438100 for VRChat. The prefix and the
                       Proton build are derived from Steam's own config.
      --proton PATH    Proton to use: a name under compatibilitytools.d or
                       steamapps/common, or an absolute path. Required if it
                       cannot be read from Steam's CompatToolMapping.
      --prefix DIR     Compat data dir (the one containing pfx/). Overrides
                       --appid for locating the prefix.
      --payload DIR    Spout2PW payload dir. Defaults to the copy under
                       $XDG_DATA_HOME, falling back to this package's own.
      --uninstall      Remove the stubs and the service entry instead.
      -h, --help       Show this help.

    Requires steam-run (NixOS: programs.steam.enable = true), because Proton
    needs an FHS environment.
    USAGE
    }

    die() { echo "spout2pw-install: $*" >&2; exit 1; }

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --appid)     appid="''${2:?--appid needs a value}"; shift 2 ;;
        --proton)    proton="''${2:?--proton needs a value}"; shift 2 ;;
        --prefix)    compat_data="''${2:?--prefix needs a value}"; shift 2 ;;
        --payload)   payload="''${2:?--payload needs a value}"; shift 2 ;;
        --uninstall) uninstall=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           usage >&2; die "unknown argument: $1" ;;
      esac
    done

    # --- Steam root -----------------------------------------------------------
    steamroot=""
    for candidate in \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/Steam" \
      "$HOME/.steam/steam" \
      "$HOME/.steam/root"
    do
      if [ -d "$candidate/steamapps" ]; then steamroot="$(realpath "$candidate")"; break; fi
    done
    [ -n "$steamroot" ] || die "could not find a Steam installation"

    # --- prefix ---------------------------------------------------------------
    if [ -z "$compat_data" ]; then
      [ -n "$appid" ] || { usage >&2; die "one of --appid or --prefix is required"; }
      compat_data="$steamroot/steamapps/compatdata/$appid"
    fi
    prefix="$compat_data/pfx"
    [ -d "$prefix/drive_c" ] || die "no Wine prefix at '$prefix' (run the game once first?)"

    # Refuse to touch a prefix that is in use; wineserver rewrites system.reg on
    # exit and would clobber the service entry we are about to add.
    for pid in $(pgrep -x wineserver 2>/dev/null || true); do
      if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null \
         | grep -qxF "STEAM_COMPAT_DATA_PATH=$compat_data"; then
        die "a wineserver is running for this prefix (pid $pid) - close the game first"
      fi
    done

    # --- proton ---------------------------------------------------------------
    if [ -z "$proton" ] && [ -n "$appid" ] && [ -r "$steamroot/config/config.vdf" ]; then
      proton="$(awk -v appid="\"$appid\"" '
        /"CompatToolMapping"/ { in_map = 1 }
        in_map && $1 == appid { found = 1; next }
        found && $1 == "\"name\"" { gsub(/"/, "", $2); print $2; exit }
      ' "$steamroot/config/config.vdf")"
      [ -n "$proton" ] && echo "Detected Proton for $appid: $proton"
    fi
    [ -n "$proton" ] || die "could not determine the Proton build; pass --proton"

    if [ ! -d "$proton" ]; then
      for candidate in \
        "$steamroot/compatibilitytools.d/$proton" \
        "$steamroot/steamapps/common/$proton"
      do
        if [ -d "$candidate" ]; then proton="$candidate"; break; fi
      done
    fi
    [ -x "$proton/proton" ] || die "no Proton at '$proton' (pass --proton with a full path)"

    # --- payload --------------------------------------------------------------
    if [ -z "$payload" ]; then
      if [ -e "$default_payload/spout2pw.inf" ]; then
        payload="$default_payload"
      else
        payload="$packaged_payload"
      fi
    fi
    [ -e "$payload/spout2pw.inf" ] || die "no spout2pw.inf under '$payload'"
    payload="$(realpath "$payload")"

    command -v steam-run >/dev/null 2>&1 \
      || die "steam-run not found on PATH; Proton needs an FHS environment"

    echo "Steam root: $steamroot"
    echo "Prefix:     $prefix"
    echo "Proton:     $proton"
    echo "Payload:    $payload"

    system32="$prefix/drive_c/windows/system32"
    syswow64="$prefix/drive_c/windows/syswow64"

    run_in_prefix() {
      # WINEDLLPATH must stay unset: with it, setupapi copies our real builtins
      # into system32 instead of writing placeholder stubs.
      env -u WINEDLLPATH \
        STEAM_COMPAT_CLIENT_INSTALL_PATH="$steamroot" \
        STEAM_COMPAT_DATA_PATH="$compat_data" \
        PROTON_VERB=run \
        steam-run "$proton/proton" run "$@"
    }

    if [ "$uninstall" = 1 ]; then
      echo "Removing Spout2PW from the prefix..."
      run_in_prefix reg delete \
        'HKLM\System\CurrentControlSet\Services\Spout2Pw' /f >/dev/null 2>&1 || true
      rm -f "$system32/spout2pw.exe" "$system32/spoutdxtoc.dll" \
            "$syswow64/spout2pw.exe" "$syswow64/spoutdxtoc.dll"
      echo "Done. (Steam may still re-create the prefix from scratch if you ask it to.)"
      exit 0
    fi

    # Stale copies would be picked up ahead of the 64-bit ones.
    rm -f "$syswow64/spout2pw.exe" "$syswow64/spoutdxtoc.dll"
    # An existing binary can be locked by a running service; drop it first.
    rm -f "$system32/spout2pw.exe"

    inf_win="Z:''${payload//\//\\}\\spout2pw.inf"
    echo "Installing $inf_win ..."
    run_in_prefix cmd.exe /c \
      "rundll32 setupapi.dll,InstallHinfSection DefaultInstall 128 $inf_win"

    # --- verify ---------------------------------------------------------------
    fail=0
    for f in spout2pw.exe spoutdxtoc.dll; do
      if [ ! -e "$system32/$f" ]; then
        echo "MISSING: system32/$f" >&2; fail=1
      elif ! grep -qa "Wine placeholder DLL" "$system32/$f"; then
        echo "NOT A PLACEHOLDER: system32/$f" >&2; fail=1
      else
        echo "ok: system32/$f"
      fi
    done

    if grep -q 'Services\\\\Spout2Pw' "$prefix/system.reg"; then
      echo "ok: Spout2Pw service registered"
    else
      echo "MISSING: Spout2Pw service registration" >&2; fail=1
    fi

    [ "$fail" = 0 ] || die "installation did not complete"

    echo
    echo "Done. Add to the game's Steam launch options:"
    echo "  WINEDLLPATH=$payload/spout2pw-dlls %command%"
    echo "(and SPOUT2PW_WINE10=1 when running under Proton 10)"
  '';

  meta = {
    description = "Install Spout2PW into a Proton/Wine prefix";
    mainProgram = "spout2pw-install";
  };
}

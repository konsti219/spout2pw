# Spout2PW: Spout2 to PipeWire bridge

**[Spout2PW website](https://spout2pw.lina.yt)**

[![Github-sponsors](https://img.shields.io/github/sponsors/hoshinolina?label=Sponsor&logo=GitHub)](https://lina.yt/sponsor)
[![Ko-Fi](https://shields.io/badge/ko--fi-Tip-ff5f5f?logo=ko-fi)](https://lina.yt/kofi)

**If you like this, please help support me with the links above!**

See the [wiki page](https://github.com/hoshinolina/spout2pw/wiki) for installation and usage instructions.

## Installing on NixOS

This fork ships a flake with `spout2pw`, the `obs-pwvideo` receiver, a
`spout2pw-install` helper, and a Home Manager module.

**1. Add the flake input**

```nix
inputs.spout2pw = {
  url = "github:konsti219/spout2pw";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

**2. Enable the Home Manager module**

```nix
imports = [inputs.spout2pw.homeModules.default];
programs.spout2pw.enable = true;
```

**3. Steam environment**

`pressure-vessel` looks for the GBM backend in its own overrides directory and
never populates it on NixOS, because Mesa lives at a non-FHS store path. Without
this, streams fail with `Failed to set up Vulkan for stream`:

```nix
programs.steam.package = pkgs.steam.override {
  extraProfile = ''
    export GBM_BACKENDS_PATH="$(realpath /run/opengl-driver/lib/gbm)"
    export PRESSURE_VESSEL_FILESYSTEMS_RO="/nix/store''${PRESSURE_VESSEL_FILESYSTEMS_RO:+:$PRESSURE_VESSEL_FILESYSTEMS_RO}"
  '';
};
```

**4. Seed the Wine prefix (once per prefix)**

```bash
spout2pw-install --appid 438100        # or: nix run github:konsti219/spout2pw#install -- --appid 438100
```

This installs the fakedll stubs and registers the `Spout2Pw` service, by driving
Proton's own `setupapi` installer. It reads the prefix and Proton build from
Steam's config; pass `--proton`/`--prefix` to override, `--uninstall` to undo.
Close the game first. Re-run it after Steam recreates the prefix.

**5. Set the game's launch options**

```
WINEDLLPATH=/home/<user>/.local/share/spout2pw/spout2pw-dlls %command%
```

Add `SPOUT2PW_WINE10=1` on Proton 10; omit it on Proton 11. Then enable
Stream Camera → Spout in the app, and add a PipeWire Video source in OBS.

## Building

```bash
git submodule init
git submodule update
./build.sh
```

This creates a package at `build/pkg`.

## Build dependencies

On Debian: `sudo apt install meson ninja-build libdbus-1-dev libwine-dev mingw-w64 libgbm-dev libdrm-dev libvulkan-dev wine64-tools`

## Credits
Original author:
* hoshinolina

Based on a prototype by tytan652:

* https://codeberg.org/tytan652/spoutdxtoc
* https://codeberg.org/tytan652/spout2xdp

Contributors:
* hoshinolina
* marysaka
* yofukashino
* h-banii

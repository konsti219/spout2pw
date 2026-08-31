# Spout2PW: Spout2 to PipeWire bridge

**[Spout2PW website](https://spout2pw.lina.yt)**

[![Github-sponsors](https://img.shields.io/github/sponsors/hoshinolina?label=Sponsor&logo=GitHub)](https://lina.yt/sponsor)
[![Ko-Fi](https://shields.io/badge/ko--fi-Tip-ff5f5f?logo=ko-fi)](https://lina.yt/kofi)

**If you like this, please help support me with the links above!**

See the [wiki page](https://github.com/hoshinolina/spout2pw/wiki) for installation and usage instructions.

## Installing on NixOS with steam-config-nix

This fork ships the Spout2PW payload, the `obs-pwvideo` receiver, and a Home
Manager module for declarative installation through
[steam-config-nix](https://github.com/different-name/steam-config-nix). No
manual prefix setup or Steam launch-option editing is required.

**1. Add the flake input**

```nix
inputs = {
  spout2pw = {
    url = "github:konsti219/spout2pw";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  steam-config-nix = {
    url = "github:different-name/steam-config-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

**2. Enable Steam on NixOS**

```nix
programs.steam.enable = true;
```

**3. Enable both Home Manager modules**

```nix
imports = [
  inputs.steam-config-nix.homeModules.default
  inputs.spout2pw.homeModules.default
];

programs.steam.config.enable = true;

programs.spout2pw = {
  enable = true;
  apps = ["438100"]; # VRChat

  # Off by default. Only needed for apps still on Proton 10 or older.
  wine10 = false;
};
```

The module copies the DLL payload to `$XDG_DATA_HOME/spout2pw`, adds the required
environment to each listed app, and uses steam-config-nix to place the Wine
placeholder modules and service registration into each prefix. On NixOS it also
exposes the system GBM backend and its Nix store dependencies to
`pressure-vessel` for those apps. If OBS Studio is enabled through Home Manager,
the `obs-pwvideo` plugin is installed automatically.

After rebuilding, enable Stream Camera → Spout in the app and add a PipeWire
Video source in OBS.

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

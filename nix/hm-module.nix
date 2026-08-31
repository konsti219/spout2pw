{ self }:
{ config, lib, options, pkgs, ... }:

let
  cfg = config.programs.spout2pw;
  inherit (lib) mkEnableOption mkIf mkOption types;
  packages = self.packages.${pkgs.stdenv.hostPlatform.system};
  installPath = "${config.xdg.dataHome}/spout2pw";

  hasSteamConfig = lib.hasAttrByPath [ "programs" "steam" "config" "apps" ] options;
in
{
  options.programs.spout2pw = {
    enable = mkEnableOption "Spout2PW, a Spout2 to PipeWire bridge for apps running under Proton";

    apps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "438100" ];
      description = "Steam app IDs that should launch with Spout2PW available.";
    };

    wine10 = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Set `SPOUT2PW_WINE10`, which switches the receiver to the KMT
        shared-handle path that Proton 10 and older need.

        Proton 11 and newer take the Vulkan path, so only turn this on for an
        app still running on an older Proton.
      '';
    };
  };

  config = mkIf cfg.enable (lib.mkMerge [
    {
      programs.obs-studio.plugins = mkIf config.programs.obs-studio.enable [ packages.obs-pwvideo ];

      assertions = [
        {
          assertion = hasSteamConfig;
          message = "programs.spout2pw requires the steam-config-nix Home Manager module";
        }
        {
          assertion = cfg.apps != [ ];
          message = "programs.spout2pw.apps must contain at least one Steam app ID";
        }
      ] ++ lib.optional hasSteamConfig {
        assertion = config.programs.steam.config.enable;
        message = "programs.spout2pw requires programs.steam.config.enable = true";
      };

      # pressure-vessel cannot access /nix/store, so expose the DLL payload from
      # a real path under $HOME rather than through a Home Manager symlink.
      home.activation.spout2pw =
        let
          dir = lib.escapeShellArg installPath;
        in
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run rm -rf ${dir}
          run mkdir -p ${dir}
          run cp -rL --no-preserve=mode,ownership \
            ${packages.spout2pw}/share/spout2pw/spout2pw-dlls ${dir}/
        '';
    }

    # only touch steam-config-nix's options when its module is actually imported
    (lib.optionalAttrs hasSteamConfig {
      programs.steam.config.apps = lib.genAttrs cfg.apps (_appId: {
        env = {
          WINEDLLPATH = "${installPath}/spout2pw-dlls";
        } // lib.optionalAttrs cfg.wine10 { SPOUT2PW_WINE10 = "1"; };

        # NixOS's GBM backends resolve into the store, which pressure-vessel
        # does not expose by default. Set this in the per-app wrapper so only
        # games using Spout2PW inherit the workaround.
        preHook = ''
          if [ -d /run/opengl-driver/lib/gbm ]; then
            export GBM_BACKENDS_PATH="$(${lib.getExe' pkgs.coreutils "realpath"} /run/opengl-driver/lib/gbm)"
            export PRESSURE_VESSEL_FILESYSTEMS_RO="/nix/store''${PRESSURE_VESSEL_FILESYSTEMS_RO:+:$PRESSURE_VESSEL_FILESYSTEMS_RO}"
          fi
        '';

        # The placeholders mark both modules as builtin so WINEDLLPATH is
        # consulted; the service entry starts the bridge with the game.
        files.prefix = {
          place = {
            "drive_c/windows/system32/spout2pw.exe".source =
              "${packages.spout2pw-fake-modules}/spout2pw.exe";
            "drive_c/windows/system32/spoutdxtoc.dll".source =
              "${packages.spout2pw-fake-modules}/spoutdxtoc.dll";
          };

          patch."system.reg" = {
            format = "registry";
            content."System\\ControlSet001\\Services\\Spout2Pw" = {
              Description = "Spout to PipeWire bridge";
              DisplayName = "Spout2Pw";
              ImagePath = "C:\\windows\\system32\\spout2pw.exe";
              ObjectName = "LocalSystem";
              ErrorControl = 1;
              Start = 2;
              Type = 288;
            };
          };
        };
      });
    })
  ]);
}

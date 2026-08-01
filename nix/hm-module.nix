{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.spout2pw;
  inherit (lib) mkEnableOption mkIf mkOption types;
  defaults = self.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  options.programs.spout2pw = {
    enable = mkEnableOption "Spout2PW, a Spout2 to PipeWire bridge for apps running under Proton";

    package = mkOption {
      type = types.package;
      default = defaults.spout2pw;
      defaultText = "spout2pw flake's `packages.<system>.spout2pw`";
      description = "The spout2pw package providing `share/spout2pw`.";
    };

    installPath = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/spout2pw";
      defaultText = "\"\${xdg.dataHome}/spout2pw\"";
      description = ''
        Where the payload is copied to. This must be a real path under $HOME:
        Steam's pressure-vessel container does not bind-mount /nix, and the
        launcher's `steamrt_checkpath()` resolves `realpath "$0"` and rejects
        store paths. The activation script therefore copies with `-L` rather
        than symlinking into the store.
      '';
    };

    extraLauncherPackages = mkOption {
      type = types.listOf types.package;
      default = [ ];
      description = ''
        Extra packages to put on PATH for the bootstrap launcher wrapper. Steam
        invokes it inside its own FHS environment, so the wrapper supplies the
        tools `spout2pw.sh` shells out to.
      '';
    };

    obs = {
      enable = mkOption {
        type = types.bool;
        default = config.programs.obs-studio.enable;
        defaultText = "config.programs.obs-studio.enable";
        description = "Install the obs-pwvideo plugin, which receives the PipeWire stream in OBS.";
      };

      package = mkOption {
        type = types.package;
        default = defaults.obs-pwvideo;
        defaultText = "spout2pw flake's `packages.<system>.obs-pwvideo`";
        description = "The obs-pwvideo package.";
      };
    };
  };

  config = mkIf cfg.enable {
    programs.obs-studio.plugins = mkIf cfg.obs.enable [ cfg.obs.package ];

    # Copy the payload out of the store into $HOME. See `installPath` for why
    # this cannot be a home.file symlink.
    #
    # Steady-state Steam launch options need only:
    #
    #   WINEDLLPATH=<installPath>/spout2pw-dlls %command%
    #
    # plus SPOUT2PW_WINE10=1 when running under Proton 10 (drop it on Proton 11).
    #
    # A *fresh* Wine prefix must be seeded once, which needs the launcher's
    # .inf/fakedll/service install: temporarily prepend
    # `<installPath>/spout2pw-wrapped.sh` to the launch options, start the game
    # once, then remove it again.
    home.activation.spout2pw =
      let
        wrapper = pkgs.writeShellScript "spout2pw-wrapped.sh" ''
          export PATH="${lib.makeBinPath (cfg.package.passthru.launcherRuntimeDeps or [ ] ++ cfg.extraLauncherPackages)}:$PATH"
          exec "$(dirname "$(realpath "$0")")/spout2pw.sh" "$@"
        '';
        dir = lib.escapeShellArg cfg.installPath;
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run rm -rf ${dir}
        run mkdir -p ${dir}
        run cp -rL --no-preserve=mode,ownership ${cfg.package}/share/spout2pw/. ${dir}
        run chmod -R u+w ${dir}
        run install -m755 ${wrapper} ${lib.escapeShellArg "${cfg.installPath}/spout2pw-wrapped.sh"}
      '';
  };
}

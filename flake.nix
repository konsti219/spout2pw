{
  description = "Standalone Spout2PW flake for local development and packaging";

  # Subproject sources are plain fetchFromGitHub calls in nix/spout2pw.nix, not
  # flake inputs, so nixpkgs is the only thing to lock here.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      version = "0.2.7-unstable-${builtins.substring 0 8 (self.lastModifiedDate or "19700101")}";
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = spout2pw;
        spout2pw = pkgs.callPackage ./nix/spout2pw.nix { inherit version; };
        obs-pwvideo = pkgs.callPackage ./nix/obs-pwvideo.nix { };
        spout2pw-fake-modules = pkgs.callPackage ./nix/fake-modules.nix { };
      });

      # For in-tree iteration: `nix develop -c ./build.sh` against the real git
      # submodules, so edits don't need a flake rebuild round-trip.
      devShells = forAllSystems (pkgs:
        let spout2pw = self.packages.${pkgs.stdenv.hostPlatform.system}.spout2pw;
        in {
          default = pkgs.mkShell {
            inputsFrom = [ spout2pw ];
            packages = [ pkgs.git ];
          };
        });

      homeModules = {
        default = self.homeModules.spout2pw;
        spout2pw = import ./nix/hm-module.nix { inherit self; };
      };

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}

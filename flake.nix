{
  description = "Standalone Spout2PW flake for local development and packaging";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # The meson subprojects are git submodules, which a flake `src` cannot see.
    # Pin them as non-flake inputs instead, so flake.lock is the packaging pin
    # (and `nix flake update` bumps them) while the submodules stay the pin for
    # in-tree `./build.sh` development. Keep the two in sync when bumping.
    libfunnel = {
      url = "github:hoshinolina/libfunnel/779586dab6ad396ce4a363204c8b9a18f473ca5d";
      flake = false;
    };
    pipewire-static = {
      url = "github:hoshinolina/pipewire-static/5b36797b30574cab48097010e177faf32e8fe245";
      flake = false;
    };
    spoutdxtoc = {
      url = "github:tasokait/spoutdxtoc/6393b7dfb1f1b0309111889f4ae1e68be1917d3b";
      flake = false;
    };
    spout2 = {
      url = "github:leadedge/Spout2/f49e2f469f8cb25f559a6eaa61a3f5b8173fc100";
      flake = false;
    };
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , ...
    }@inputs:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
    let
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # Wine is pinned to the *stable* (11.0) series on purpose. It supplies the
      # PE import libs and Windows headers for the cross build, and 11.0 is the
      # base of both Proton 11 and (ABI-compatibly) Proton 10 for the parts this
      # project touches. `wineWow64Packages.unstable` is already 11.12, whose
      # wineserver protocol (952) is far from anything Proton ships.
      wine = pkgs.wineWow64Packages.stable;

      mingw = pkgs.pkgsCross.mingwW64.stdenv.cc;

      # Everything the launcher shells out to. Steam invokes it inside its own
      # FHS environment, where none of these are on PATH.
      launcherRuntimeDeps = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.pipewire # pw-dump, for the version gate
        pkgs.kdePackages.kdialog
        pkgs.util-linux
        pkgs.which
      ];

      # `build.sh`'s PipeWire configuration: a static libpipewire with everything
      # we don't need switched off. Kept in the same order as upstream so the two
      # can be diffed by eye when `build.sh` changes.
      pipewireStaticFlags = [
        "-Dexamples=disabled"
        "-Dtests=disabled"
        "-Dgstreamer=disabled"
        "-Dlibsystemd=disabled"
        "-Dlogind=disabled"
        "-Dselinux=disabled"
        "-Dpipewire-alsa=disabled"
        "-Dpipewire-jack=disabled"
        "-Dpipewire-v4l2=disabled"
        "-Dspa-plugins=enabled"
        "-Dudev=disabled"
        "-Dsdl2=disabled"
        "-Dv4l2=disabled"
        "-Dalsa=disabled"
        "-Dx11=disabled"
        "-Dlibffado=disabled"
        "-Dsnap=disabled"
        "-Dopus=disabled"
        "-Dreadline=disabled"
        "-Dgsettings=disabled"
        "-Dsession-managers=[]"
        "-Ddefault_library=static"
        "-Djack=disabled"
        "-Davahi=disabled"
        "-Draop=disabled"
        "-Davb=disabled"
        "-Dlibpulse=disabled"
        "-Dflatpak=disabled"
        "-Dsupport=enabled"
        "-Dstatic=true"
        "-Dlibdir=lib"
      ];

      spout2pw = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "spout2pw";
        version = "0.2.7-unstable-${builtins.substring 0 8 (self.lastModifiedDate or "0")}";

        src = lib.cleanSourceWith {
          name = "spout2pw-src";
          src = ./.;
          filter = path: type:
            let rel = lib.removePrefix (toString ./. + "/") (toString path);
            in
            !(lib.hasPrefix "build" rel
              || lib.hasPrefix "subprojects/" rel
              || lib.hasPrefix ".direnv" rel
              || lib.hasPrefix ".cache" rel
              || lib.hasPrefix "result" rel);
        };

        strictDeps = true;

        nativeBuildInputs = [
          pkgs.meson
          pkgs.ninja
          pkgs.pkg-config
          pkgs.makeWrapper
          wine # winegcc, plus the PE import libs and headers
          mingw # x86_64-w64-mingw32-{gcc,g++,ar,windres,strip}
        ];

        buildInputs = [
          pkgs.dbus
          pkgs.libdrm
          pkgs.libgbm
          pkgs.vulkan-headers
          pkgs.vulkan-loader
        ];

        # Drop in the submodule sources the flake `src` filtered out. meson writes
        # into subproject directories, so they have to be writable copies.
        postPatch = ''
          # meson exec's these directly at configure/install time and they are
          # `#!/bin/bash`, which does not exist in the build sandbox.
          patchShebangs tools

          # Copy *contents* (`/.`) into pre-created dirs: the fetched spoutdxtoc
          # tree already carries an empty Spout2/ submodule placeholder, and
          # `cp -r src dst` would nest into it rather than populate it.
          for sub in libfunnel pipewire-static spoutdxtoc spoutdxtoc/Spout2; do
            install -d "subprojects/$sub"
          done
          cp -r --no-preserve=mode,ownership ${inputs.libfunnel}/. subprojects/libfunnel/
          cp -r --no-preserve=mode,ownership ${inputs.pipewire-static}/. subprojects/pipewire-static/
          cp -r --no-preserve=mode,ownership ${inputs.spoutdxtoc}/. subprojects/spoutdxtoc/
          cp -r --no-preserve=mode,ownership ${inputs.spout2}/. subprojects/spoutdxtoc/Spout2/
          chmod -R u+w subprojects
        '';

        # `tools/get_wine_path.sh` probes winegcc, which wants a writable HOME.
        configurePhase = ''
          runHook preConfigure

          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"

          pwPrefix="$PWD/build-pw-prefix"

          echo "=== stage 1: static libpipewire ==="
          meson setup build-pw subprojects/pipewire-static \
            -Dprefix="$pwPrefix/usr" \
            ${lib.escapeShellArgs pipewireStaticFlags}
          ninja -C build-pw
          ninja -C build-pw install

          echo "=== stage 2: spout2pw (mingw cross + native unixlib) ==="
          # meson's native-file pkg_config_path *replaces* the environment's, so
          # append stdenv's or the native libfunnel build loses gbm/libdrm/vulkan.
          cat > native.txt <<EOF
          [built-in options]
          pkg_config_path='$pwPrefix/usr/lib/pkgconfig:$PKG_CONFIG_PATH'
          EOF

          meson setup build \
            --native-file native.txt \
            --cross-file misc/x86_64-w64-mingw32.txt \
            -Dlibpipewire_static_lib="$pwPrefix/usr/lib/libpipewire-static-0.3.a" \
            || { cat build/meson-logs/meson-log.txt; false; }

          runHook postConfigure
        '';

        buildPhase = ''
          runHook preBuild
          ninja -C build
          runHook postBuild
        '';

        # `ninja install` runs tools/package.sh, which assembles the payload in
        # build/pkg: the launcher, the .inf, and the PE/unix DLL pair stamped with
        # the "Wine builtin DLL" marker at offset 64.
        installPhase = ''
          runHook preInstall

          ninja -C build install

          mkdir -p "$out/share/spout2pw"
          cp -r build/pkg/. "$out/share/spout2pw"

          runHook postInstall
        '';

        # $out/bin/spout2pw is for manual/bootstrap use. The copy under $HOME that
        # Steam points at is produced by the home-manager activation script, which
        # must copy rather than symlink: pressure-vessel does not bind-mount /nix,
        # and the launcher's steamrt_checkpath() resolves realpath "$0".
        postFixup = ''
          makeWrapper "$out/share/spout2pw/spout2pw.sh" "$out/bin/spout2pw" \
            --prefix PATH : ${lib.makeBinPath launcherRuntimeDeps}
        '';

        meta = {
          description = "Spout2 to PipeWire bridge, for capturing Windows apps under Proton";
          homepage = "https://github.com/konsti219/spout2pw";
          license = lib.licenses.gpl2Only;
          platforms = [ "x86_64-linux" ];
          mainProgram = "spout2pw";
        };
      });

      obs-pwvideo = pkgs.stdenv.mkDerivation (finalAttrs: {
        pname = "obs-pwvideo";
        version = "0.2.4";

        src = pkgs.fetchFromGitHub {
          owner = "hoshinolina";
          repo = "obs-pwvideo";
          tag = finalAttrs.version;
          hash = "sha256-CCzeK5JyCWnIcty5xaDV5uCxvrMVx50f8SoLZnlF658=";
        };

        nativeBuildInputs = [
          pkgs.cmake
          pkgs.ninja
          pkgs.pkg-config
          pkgs.qt6.wrapQtAppsHook
        ];

        buildInputs = [
          pkgs.libdrm
          pkgs.obs-studio # libobs + obs-frontend-api cmake configs
          pkgs.pipewire
          pkgs.qt6.qtbase
        ];

        cmakeFlags = [
          (lib.cmakeFeature "CMAKE_BUILD_TYPE" "RelWithDebInfo")
        ];

        meta = {
          description = "Generic PipeWire video source for OBS Studio";
          homepage = "https://github.com/hoshinolina/obs-pwvideo";
          license = lib.licenses.gpl2Plus;
          platforms = [ "x86_64-linux" ];
        };
      });
    in
    {
      packages = {
        default = spout2pw;
        inherit spout2pw obs-pwvideo;
      };

      apps.default = {
        type = "app";
        program = "${spout2pw}/bin/spout2pw";
      };

      # For in-tree iteration: `nix develop -c ./build.sh` against the real git
      # submodules, so edits don't need a flake rebuild round-trip.
      devShells.default = pkgs.mkShell {
        inputsFrom = [ spout2pw ];
        packages = launcherRuntimeDeps ++ [ pkgs.git ];
      };

      formatter = pkgs.nixpkgs-fmt;
    });
}

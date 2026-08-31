{ lib
, stdenv
, fetchFromGitHub
, dbus
, libdrm
, libgbm
, meson
, ninja
, pkg-config
, pkgsCross
, vulkan-headers
, vulkan-loader
, wineWow64Packages
, version ? "0.2.7-unstable"
}:

let
  # The meson subprojects are git submodules. A flake `src` cannot see submodule
  # contents, so fetch them here instead. These revs are exactly what
  # `git submodule update --init --recursive` checks out -- keep them in sync
  # when bumping the submodules.
  subprojects = {
    libfunnel = fetchFromGitHub {
      owner = "hoshinolina";
      repo = "libfunnel";
      rev = "779586dab6ad396ce4a363204c8b9a18f473ca5d";
      hash = "sha256-eBuWoE13PDWePSzxCNVFnuM0SRZ/HxzUtSgs0SFHu/c=";
    };
    pipewire-static = fetchFromGitHub {
      owner = "hoshinolina";
      repo = "pipewire-static";
      rev = "5b36797b30574cab48097010e177faf32e8fe245";
      hash = "sha256-n9Sqc6JV8ZhgpKmYVpou3vaY5UrgDdl8RBQRjiSc+ts=";
    };
    spoutdxtoc = fetchFromGitHub {
      owner = "tasokait";
      repo = "spoutdxtoc";
      rev = "8ba7495aa9e8ea5549e9f894ad2cbec6315f1c42";
      hash = "sha256-mMpLBPvPnWbYfgWOUZ9c2GbCZYQEIAr3kMbMXj6cCf0=";
    };
    spout2 = fetchFromGitHub {
      owner = "leadedge";
      repo = "Spout2";
      rev = "f49e2f469f8cb25f559a6eaa61a3f5b8173fc100";
      hash = "sha256-fAu47W7UOD6smAPLECacHqMb5K2r57zQjpnsF8DfKKA=";
    };
  };

  # Wine is pinned to the *stable* (11.0) series on purpose. It supplies the PE
  # import libs and Windows headers for the cross build, and 11.0 is the base of
  # both Proton 11 and (ABI-compatibly) Proton 10 for the parts this project
  # touches. `wineWow64Packages.unstable` is already 11.12, whose wineserver
  # protocol (952) is far from anything Proton ships.
  wine = wineWow64Packages.stable;

  mingw = pkgsCross.mingwW64.stdenv.cc;

  # `build.sh`'s PipeWire configuration: a static libpipewire with everything we
  # don't need switched off. Kept in upstream's order so the two can be diffed by
  # eye when build.sh changes.
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

  root = ../.;
in
stdenv.mkDerivation {
  pname = "spout2pw";
  inherit version;

  src = lib.cleanSourceWith {
    name = "spout2pw-src";
    src = root;
    filter = path: _type:
      let rel = lib.removePrefix (toString root + "/") (toString path);
      in
      !(lib.hasPrefix "build" rel
        || lib.hasPrefix "subprojects/" rel
        || lib.hasPrefix ".direnv" rel
        || lib.hasPrefix ".cache" rel
        || lib.hasPrefix "result" rel);
  };

  strictDeps = true;

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wine # winegcc, plus the PE import libs and headers
    mingw # x86_64-w64-mingw32-{gcc,g++,ar,windres,strip}
  ];

  buildInputs = [
    dbus
    libdrm
    libgbm
    vulkan-headers
    vulkan-loader
  ];

  postPatch = ''
    # meson exec's these directly at configure/install time and they are
    # `#!/bin/bash`, which does not exist in the build sandbox.
    patchShebangs tools

    # Drop in the subproject sources that the `src` filter excluded. Copy
    # *contents* (`/.`) into pre-created dirs: the fetched spoutdxtoc tree
    # already carries an empty Spout2/ submodule placeholder, and
    # `cp -r src dst` would nest into it rather than populate it. meson also
    # writes into subproject dirs, so they must be writable.
    for sub in libfunnel pipewire-static spoutdxtoc spoutdxtoc/Spout2; do
      install -d "subprojects/$sub"
    done
    cp -r --no-preserve=mode,ownership ${subprojects.libfunnel}/. subprojects/libfunnel/
    cp -r --no-preserve=mode,ownership ${subprojects.pipewire-static}/. subprojects/pipewire-static/
    cp -r --no-preserve=mode,ownership ${subprojects.spoutdxtoc}/. subprojects/spoutdxtoc/
    cp -r --no-preserve=mode,ownership ${subprojects.spout2}/. subprojects/spoutdxtoc/Spout2/
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
      -Dlibpipewire_static=true \
      -Dlibpipewire_static_lib="$pwPrefix/usr/lib/libpipewire-static-0.3.a" \
      || { cat build/meson-logs/meson-log.txt; false; }

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ninja -C build
    runHook postBuild
  '';

  # `ninja install` runs tools/package.sh, which stamps the PE files with the
  # "Wine builtin DLL" marker. The declarative setup only needs its DLL tree.
  installPhase = ''
    runHook preInstall

    ninja -C build install

    mkdir -p "$out/share/spout2pw"
    cp -r build/pkg/spout2pw-dlls "$out/share/spout2pw/"

    runHook postInstall
  '';

  meta = {
    description = "Spout2 to PipeWire bridge, for capturing Windows apps under Proton";
    homepage = "https://github.com/konsti219/spout2pw";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}

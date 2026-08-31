{ lib
, stdenv
, fetchFromGitHub
, cmake
, libdrm
, ninja
, obs-studio
, pipewire
, pkg-config
, qt6
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "obs-pwvideo";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "hoshinolina";
    repo = "obs-pwvideo";
    tag = finalAttrs.version;
    hash = "sha256-CCzeK5JyCWnIcty5xaDV5uCxvrMVx50f8SoLZnlF658=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    libdrm
    obs-studio # libobs + obs-frontend-api cmake configs
    pipewire
    qt6.qtbase
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
})

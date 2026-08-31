{ lib
, runCommand
, wineWow64Packages
}:

# Wine placeholder modules for spout2pw.exe and spoutdxtoc.dll.
#
# Wine's loader only treats a module as builtin when a file of that name exists
# in system32 carrying the "Wine placeholder DLL" marker; the real code is then
# loaded from WINEDLLPATH. winebuild emits the stubs at build time so
# steam-config-nix can seed each prefix declaratively.
let
  # Same pin as spout2pw itself: the base of both Proton 10 and 11.
  wine = wineWow64Packages.stable;
in
runCommand "spout2pw-fake-modules" { } ''
  mkdir -p $out
  : > empty.spec
  ${lib.getExe' wine "winebuild"} --fake-module --exe \
    -b x86_64-windows --subsystem windows \
    -F spout2pw.exe -E empty.spec -o $out/spout2pw.exe
  ${lib.getExe' wine "winebuild"} --fake-module --dll \
    -b x86_64-windows --subsystem windows \
    -F spoutdxtoc.dll -E empty.spec -o $out/spoutdxtoc.dll

  for f in $out/spout2pw.exe $out/spoutdxtoc.dll; do
    grep -qa "Wine placeholder DLL" "$f" || {
      echo "winebuild did not produce a placeholder: $f" >&2
      exit 1
    }
  done
''

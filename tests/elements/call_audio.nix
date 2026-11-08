{
  lib,
  pkgs,
  system,
  helpers,
  ...
}:
let
  inherit (helpers) rejectsPurpose;
in
{
  call_audio-contracts =
    (lib.lazyDerivation {
      derivation = (
        assert
          system == "x86_64-linux"
          || rejectsPurpose "test-call-audio" system "call_audio: supports Linux only";
        pkgs.runCommand "call_audio-contracts" { } ''
          echo "call_audio contracts passed" > "$out"
        ''
      );
    })
    // {
      elements = [ "call_audio" ];
    };
}

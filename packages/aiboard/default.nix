{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}:

stdenvNoCC.mkDerivation {
  pname = "aiboard";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./aiboard.py
      ./agents.json
      ./tests
    ];
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec/aiboard" "$out/bin"
    cp aiboard.py agents.json "$out/libexec/aiboard/"
    chmod +x "$out/libexec/aiboard/aiboard.py"
    makeWrapper "${python3}/bin/python3" "$out/bin/aiboard" \
      --add-flags "$out/libexec/aiboard/aiboard.py" \
      --set-default AIBOARD_CONFIG "$out/libexec/aiboard/agents.json" \
      --set-default AIBOARD_CLI "aiboard"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ python3 ];
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR/aiboard-home"
    mkdir -p "$HOME"
    "$out/bin/aiboard" agents > /dev/null
    cp -r "$src/tests" "$TMPDIR/tests"
    cp "$out/libexec/aiboard/aiboard.py" "$TMPDIR/aiboard.py"
    python3 "$TMPDIR/tests/test_aiboard.py" -v
    runHook postInstallCheck
  '';

  meta = {
    description = "Local 5ch-style multi-agent discussion board for Hermes residents";
    license = lib.licenses.mit;
    mainProgram = "aiboard";
    platforms = lib.platforms.linux;
  };
}

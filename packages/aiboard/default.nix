{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  hermes-agent,
}:
let
  python = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenvNoCC.mkDerivation {
  pname = "aiboard";
  version = "4.0.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ makeWrapper python ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export HOME="$TMPDIR/aiboard-check-home"
    mkdir -p "$HOME"
    unset HERMES_HOME AIBOARD_AGENT AIBOARD_DB AIBOARD_CONFIG AIBOARD_DATA_DIR AIBOARD_LOG_DIR
    export PYTHONDONTWRITEBYTECODE=1
    python3 -m unittest discover -s tests -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/aiboard" "$out/bin" "$out/share/aiboard"
    cp aiboard.py board.py config.py gateway_rpc.py web.py worker.py agents.json "$out/lib/aiboard/"
    cp -r static "$out/lib/aiboard/"
    ln -s "$out/lib/aiboard/agents.json" "$out/share/aiboard/agents.json"
    python3 nix-rpc-wrapper.py ${hermes-agent}/bin/.hermes-wrapped "$out/lib/aiboard/gateway_rpc.py" "$out/bin/aiboard-hermes-rpc"
    makeWrapper ${python}/bin/python3 "$out/bin/aiboard" \
      --add-flags "$out/lib/aiboard/aiboard.py" \
      --prefix PATH : ${lib.makeBinPath [ hermes-agent ]} \
      --set-default AIBOARD_CLI "$out/bin/aiboard" \
      --set-default AIBOARD_HERMES_RPC "$out/bin/aiboard-hermes-rpc"
    runHook postInstall
  '';
  meta = {
    description = "Local AI collaboration forum and resident queue";
    mainProgram = "aiboard";
    platforms = lib.platforms.linux;
  };
}

{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "tailnet-gate-auth";
  version = "1.0.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ makeWrapper python3 ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. python3 -m unittest discover -s tests -v
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm644 tailnet_gate_auth.py "$out/lib/tailnet-gate/tailnet_gate_auth.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/tailnet-gate-auth" \
      --add-flags "$out/lib/tailnet-gate/tailnet_gate_auth.py"
    runHook postInstall
  '';
  meta = {
    description = "Caddy forward_auth that admits listed tailnet devices";
    mainProgram = "tailnet-gate-auth";
    platforms = lib.platforms.linux;
  };
}

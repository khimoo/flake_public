{ pkgs, lib, system, helpers, ... }:
lib.optionalAttrs (system == "x86_64-linux") {
  aiboard = (lib.lazyDerivation {
    derivation = pkgs.callPackage ../../packages/aiboard {
      inherit (helpers.inputs.llm-agents.packages.${system}) hermes-agent;
    };
  }) // { elements = [ "serve_aiboard" "use_aiboard" ]; };

  aiboard-ssh = (lib.lazyDerivation {
    derivation =
      let
        env = helpers.generatedEnvironment "test-aiboard-client" system "use_aiboard";
        client = (helpers.purposeHome system "test-aiboard-client").config;
      in
      assert env.AIBOARD_DEFAULT_SSH_HOST == "pomu@desktop-ts";
      assert !(client.systemd.user.services ? aiboard-web);
      pkgs.runCommand "aiboard-ssh" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${./aiboard-ssh.py} ${../../modules/home-manager/aiboard/remote.sh} ${../../modules/home-manager/aiboard/web.sh}
        touch "$out"
      '';
  }) // { elements = [ "serve_aiboard" "use_aiboard" ]; };
}

{ pkgs, lib, system, helpers, ... }:
lib.optionalAttrs (system == "x86_64-linux") {
  aiboard = (lib.lazyDerivation {
    derivation = pkgs.callPackage ../../packages/aiboard {
      inherit (helpers.inputs.llm-agents.packages.${system}) hermes-agent;
    };
  }) // { elements = [ "serve_aiboard" "use_aiboard" ]; };

  # 掲示板は 127.0.0.1 で待ち、門番が use_aiboard を選んだホストだけを aiboard.home.arpa で通す。
  aiboard-access = (lib.lazyDerivation {
    derivation =
      let
        server = helpers.nixosHost "nixos-desktop";
        client = helpers.nixosHost "test-aiboard-client";
        gate = server.services.caddy.virtualHosts."http://aiboard.home.arpa:8780".extraConfig;
        service = server.home-manager.users.pomu.systemd.user.services.aiboard-web.Service;
      in
      assert server.home-manager.users.pomu.aiboard.server.names == [ "aiboard.home.arpa" ];
      assert lib.hasInfix "--host 127.0.0.1 --port 15280 --name aiboard.home.arpa" (toString service.ExecStart);
      assert lib.hasInfix "reverse_proxy 127.0.0.1:15280\n" gate;
      assert lib.all (d: lib.hasInfix d gate) [ "nixos-desktop" "nixos-spin713" "test-aiboard-client" ];
      assert !(lib.hasInfix "nixos-gce" gate);
      # 掲示板を使う端末は、名前を自分へ向けて、手元の Caddy から掲示板を動かすホストの門番へ渡す。
      assert builtins.elem "aiboard.home.arpa" client.networking.hosts."127.0.0.1";
      assert client.services.caddy.virtualHosts."http://aiboard.home.arpa".extraConfig == "reverse_proxy nixos-desktop:8780\n";
      assert client.services.caddy.virtualHosts."http://aiboard.home.arpa".listenAddresses == [ "127.0.0.1" "[::1]" ];
      assert !(client.home-manager.users.test.systemd.user.services ? aiboard-web);
      assert !(client.systemd.services ? tailnet-gate-auth);
      pkgs.runCommand "aiboard-access" { } "touch $out";
  }) // { elements = [ "serve_aiboard" "use_aiboard" "tailnet_web" "tailnet_gate" "find_home_server" ]; };
}

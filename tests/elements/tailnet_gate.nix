{ pkgs, lib, system, helpers, ... }:
lib.optionalAttrs (system == "x86_64-linux") {
  tailnet-gate = (lib.lazyDerivation {
    derivation = pkgs.callPackage ../../packages/tailnet-gate { };
  }) // { elements = [ "tailnet_gate" ]; };

  # デスクトップの実際の Caddyfile を、ポートとログの置き場所だけ変えて動かす。サンドボックスの中では
  # 接続元はどれも自分自身なので、--self の名前が通す端末に入っているかどうかで結果が決まる。
  tailnet-gate-e2e = (lib.lazyDerivation {
    derivation =
      let
        server = helpers.nixosHost "nixos-desktop";
        auth = pkgs.callPackage ../../packages/tailnet-gate { };
      in
      # 門番のポートは tailnet の側だけに開ける。
      assert lib.elem 8780 server.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
      assert !(lib.elem 8780 server.networking.firewall.allowedTCPPorts);
      pkgs.runCommand "tailnet-gate-e2e" { nativeBuildInputs = [ pkgs.caddy pkgs.curl pkgs.python3 ]; } ''
        export HOME=$TMPDIR XDG_DATA_HOME=$TMPDIR/data XDG_CONFIG_HOME=$TMPDIR/config
        mkdir -p log
        sed -e "s|/var/log/caddy/|$PWD/log/|" \
            -e 's|^http://\([a-z.]*\) {|http://\1:18080 {|' -e 's|:8780|:18780|g' -e 's|8781|18781|' \
            -e 's|127.0.0.1:15280|127.0.0.1:25281|' -e 's|nixos-desktop:18780|127.0.0.1:18780|' \
            ${server.services.caddy.configFile} > Caddyfile
        sed -i '1,/^}/c {\n\tadmin off\n}' Caddyfile
        cat > up.py <<'EOF'
        from http.server import BaseHTTPRequestHandler, HTTPServer
        class H(BaseHTTPRequestHandler):
            def do_GET(self):
                body = ("host=" + self.headers.get("Host", "")).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        HTTPServer(("127.0.0.1", 25281), H).serve_forever()
        EOF
        python3 up.py & up=$!
        wait_port() { for _ in $(seq 100); do (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null && return; sleep 0.1; done; exit 1; }
        run() {
          ${auth}/bin/tailnet-gate-auth --listen 127.0.0.1:18781 --self "$1" --tailscale /nonexistent & a=$!
          caddy run --config Caddyfile --adapter caddyfile & c=$!
          wait_port 18781; wait_port 18780; wait_port 18080; wait_port 25281
          via_client=$(curl -s -o body -w '%{http_code}' -H 'Host: aiboard.home.arpa' http://127.0.0.1:18080/)
          direct=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: aiboard.home.arpa' http://127.0.0.1:18780/)
          other=$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: other.example' http://127.0.0.1:18780/)
          kill $a $c; wait $a $c 2>/dev/null || true
        }
        run nixos-desktop
        [ "$via_client $direct $other" = "200 200 403" ] || { echo "allowed: $via_client $direct $other"; exit 1; }
        grep -qx 'host=aiboard.home.arpa' body
        run nixos-gce
        [ "$via_client $direct $other" = "403 403 403" ] || { echo "denied: $via_client $direct $other"; exit 1; }
        kill $up
        touch $out
      '';
  }) // { elements = [ "tailnet_gate" "tailnet_web" "serve_aiboard" "use_aiboard" ]; };
}

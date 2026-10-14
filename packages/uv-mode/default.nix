# uv が取得する Python と manylinux wheel は一般的な Linux 向けに動的リンクされていて、NixOS では
# そのまま起動しない。buildFHSEnv の中でだけ動くようにし、nix-ld のようにホスト全体には広げない。
# Nix の python3 で作った venv では wheel が libstdc++.so.6 を見つけられないので、uv には uv 自身が
# 取得した Python だけを使わせる。設計判断: docs/architecture/uv-mode.md
{ buildFHSEnv, writeShellScript }:

buildFHSEnv {
  name = "uv-mode";
  targetPkgs = pkgs: with pkgs; [ uv zlib stdenv.cc.cc.lib ];
  runScript = writeShellScript "uv-mode-run" ''
    export UV_PYTHON_PREFERENCE=only-managed
    if [ "$#" -eq 0 ]; then exec bash; fi
    exec "$@"
  '';
}

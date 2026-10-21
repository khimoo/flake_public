# uv が取得する Python と manylinux wheel は一般的な Linux 向けに動的リンクされていて、NixOS では
# そのまま起動しない。buildFHSEnv の中でだけ動くようにし、nix-ld のようにホスト全体には広げない。
# Nix の python3 で作った venv では wheel が libstdc++.so.6 を見つけられないので、uv には uv 自身が
# 取得した Python だけを使わせる。設計判断: docs/howtouse/cli-tools/uv-mode.md
{ buildFHSEnv, writeShellScript }:

buildFHSEnv {
  name = "uv-mode";
  targetPkgs = pkgs: with pkgs; [ uv zlib stdenv.cc.cc.lib ];
  runScript = writeShellScript "uv-mode-run" ''
    export UV_PYTHON_PREFERENCE=only-managed
    # starship がプロンプトに uv-mode と出すための目印。uv は UV_ で始まる変数を自分の設定として読むので、
    # その接頭辞を避けて IN_NIX_SHELL と同じ形にする。
    export IN_UV_MODE=1
    if [ "$#" -eq 0 ]; then exec bash; fi
    exec "$@"
  '';
}

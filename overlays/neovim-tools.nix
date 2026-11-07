# Neovim の機能の要素（config/elements/nvim_*.star）が pkg("…") で指すパッケージ。
# Starlark では Nix の関数を呼べないので、関数で作るパッケージをここで名前にする。
inputs: final: prev:
let
  system = prev.stdenv.hostPlatform.system;
  # 辞書は overlay を通さない nixpkgs で展開し、overlay の変更で作り直されないようにする。
  plain = inputs.nixpkgs.legacyPackages.${system};
in
{
  skk-jisyo-dict = plain.stdenv.mkDerivation {
    name = "skk-jisyo-dict";
    src = inputs.skk-jisyo;
    nativeBuildInputs = [ plain.gzip ];
    unpackPhase = "gzip -d < $src > $out";
    dontInstall = true;
  };
  python-debugpy = prev.python3.withPackages (ps: [ ps.debugpy ]);
}
// prev.lib.optionalAttrs (inputs.rustowl.packages ? ${system}) {
  rustowl-locked = inputs.rustowl.packages.${system}.rustowl;
  rustowl-nvim-locked = inputs.rustowl.packages.${system}.rustowl-nvim;
}

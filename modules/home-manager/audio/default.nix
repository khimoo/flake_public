# オーディオ制作環境（Home Manager）
# DAW、楽器プラグイン、楽譜、ユーティリティをサブモジュールで分割管理
# 各サブモジュールは settings.features.audio で個別にゲートされる

{ ... }:

{
  imports = [
    ./daw.nix
    ./instruments.nix
    ./notation.nix
    ./plugin-paths.nix
    ./utilities.nix
  ];
}

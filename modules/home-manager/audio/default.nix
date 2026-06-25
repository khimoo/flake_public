# オーディオ制作環境（Home Manager）
# DAW、楽器プラグイン、ユーティリティをサブモジュールで分割管理
# 各サブモジュールは settings.features.audio で個別にゲートされる

{ ... }:

{
  imports = [
    ./daw.nix
    ./instruments.nix
    ./plugin-paths.nix
    ./utilities.nix
  ];
}

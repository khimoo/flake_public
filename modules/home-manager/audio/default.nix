# オーディオ制作環境（Home Manager）
# 伴奏の生成、DAW、楽器プラグイン、楽譜、ユーティリティをサブモジュールで分割管理
# 各サブモジュールは config.local.profile.features.audio で個別にゲートされる

{ ... }:

{
  imports = [
    ./accompaniment.nix
    ./daw.nix
    ./instruments.nix
    ./notation.nix
    ./plugin-paths.nix
    ./utilities.nix
  ];
}

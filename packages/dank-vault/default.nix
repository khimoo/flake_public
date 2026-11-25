# DankMaterialShell のパスワードマネージャー連携ランチャープラグイン DankVault（v0.4.1）。
# rbw（Bitwarden CLI）等を自動検出し、DMS ランチャーの "@" プレフィックスから検索・コピーできる。
{ fetchFromGitHub }:
fetchFromGitHub {
  owner = "alcxyz";
  repo = "DankVault";
  rev = "afb7ea46cc9bb0d85895ce4cf09e3121732e463e";
  hash = "sha256-wmoWsCAWjkpAS3vJxR/R61rwRzzpEsvlTs1V4evuY+4=";
}

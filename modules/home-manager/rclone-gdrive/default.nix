# Zotero PDF の Google Drive 双方向同期（rclone bisync + watchexec）。
#
# 全環境共通の homeModules に登録されるが、実体は settings.features.zoteroSync が
# 真のときだけ import される。無効な環境（WSL 等）では sops-nix ホームモジュールも
# 含めて一切読み込まれず、footprint はゼロになる。
#
# 使い方・鍵運用: docs/howtouse/zotero-gdrive-sync.md
# 設計判断:       docs/architecture/zotero-gdrive-sync.md
{ inputs, settings, lib, ... }:
{
  imports = lib.optionals (settings.features.zoteroSync or false) [
    inputs.sops-nix.homeManagerModules.sops
    ./impl.nix
  ];
}

# papis に関するもの一式（CLI 本体 + 宣言的設定 + ライブラリの Google Drive 同期）を
# まとめるモジュール。
#
# - app.nix : papis 本体と programs.papis 設定。GUI 環境で導入（gui feature で self-gate）
# - sync.nix: papis ライブラリ（~/papis-library）の Google Drive 双方向同期
#             （rclone bisync + watchexec）。settings.features.referenceSync が真のときだけ
#             sops-nix ごと import する。無効な環境（WSL 等）では sops も含め一切
#             読み込まれず footprint はゼロ。
#
# ディレクトリ名は volatile な同期 backend（rclone-gdrive）でも特定ツール名でもなく、
# 参照文献マネージャという安定したドメイン（papis）で付けている。backend を NAS 等へ
# 差し替えても sync.nix の差し替えで済み、app.nix・ディレクトリ名は不変。
#
# 使い方・鍵運用: docs/howtouse/papis-gdrive-sync.md
# 設計判断:       docs/architecture/papis-gdrive-sync.md
{ inputs, settings, lib, ... }:
{
  imports = [ ./app.nix ]
    ++ lib.optionals (settings.features.referenceSync or false) [
      inputs.sops-nix.homeManagerModules.sops
      ./sync.nix
    ];
}
